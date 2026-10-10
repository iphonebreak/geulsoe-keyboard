import Compression
import Foundation

/// xlsx 엔트리의 deflate(방식 8)를 푼다 — **출력 상한 + 1바이트에서 멈춘다**(PDR 6-5 「스트리밍 inflate에 출력 상한」, AC-34).
///
/// - OS `Compression`의 `COMPRESSION_ZLIB`는 **raw DEFLATE(RFC 1951)** 다 — 애플 문서 `compression/compression_zlib`
///   「The encoded format is the raw DEFLATE format as described in IETF RFC 1951」, 같은 인코더 설정은 `deflateInit2(…, -15, …)`
///   (windowBits 음수 = zlib 머리·adler32 없음). ZIP 엔트리의 방식 8이 바로 이 형식이라 머리를 떼거나 붙이지 않는다(Context7 조회 2026-10-07).
/// - 입력은 중앙 디렉터리가 말한 압축 크기 범위뿐이다. 스트림이 **그 범위 끝에서 정확히 끝나야** 한다 — 끝 표시 뒤에 바이트가 남거나,
///   끝 표시 없이 입력이 떨어지면 손상(6-5a 「모자라거나 남으면 거부」).
/// - ★ **남는 바이트는 `src_size`로 알 수 없다(실측 2026-10-07, macOS 27 SDK).** 문서는 「끝 표시 뒤 원본 버퍼에 데이터가 남을 수 있다」고
///   하지만, 실제 디코더는 끝 표시를 만나면 **준 입력을 전부 소비한 것으로**(`src_size` 0) 보고한다 — 끝 뒤 0x00·0xAB 1~4바이트 모두.
///   그래서 입력을 둘로 나눠 준다: **마지막 1바이트 전까지**(마무리 플래그 없이) → **마지막 1바이트**(마무리). 앞 단계에서 끝 표시가 나오면
///   스트림이 범위보다 일찍 끝난 것(남는 바이트)이다. 정상 deflate의 끝 표시 마지막 비트는 반드시 마지막 바이트에 있다.
/// - 출력은 메모리에만 쌓는다(파일 시스템 0). 실패는 내용 없는 코드다.
enum XLSXInflater {

    enum Failure: Error, Equatable, Sendable {
        /// 출력이 상한을 넘었다 — 상한 + 1바이트까지만 만들고 멈췄다
        case exceedsLimit
        /// deflate가 아니거나, 잘렸거나, 끝 뒤에 바이트가 남았다
        case corrupt
    }

    /// 한 번에 푸는 출력 조각 — 상한까지 이만큼씩 늘린다
    static let chunkBytes = 64 * 1024

    static func inflate(_ input: [UInt8], limit: Int) -> Result<[UInt8], Failure> {
        inflate(input[...], limit: limit)
    }

    static func inflate(_ input: ArraySlice<UInt8>, limit: Int) -> Result<[UInt8], Failure> {
        guard !input.isEmpty, limit >= 0 else { return .failure(.corrupt) }
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            return .failure(.corrupt)
        }
        defer { compression_stream_destroy(stream) }

        let chunk = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkBytes)
        defer { chunk.deallocate() }
        var output: [UInt8] = []
        let finalize = Int32(bitPattern: COMPRESSION_STREAM_FINALIZE.rawValue)

        return input.withUnsafeBufferPointer { source -> Result<[UInt8], Failure> in
            guard let base = source.baseAddress else { return .failure(.corrupt) }
            // 앞 단계: 마지막 1바이트 전까지, 마무리 플래그 없이 — 여기서 끝나면 범위 끝에 남는 바이트가 있다
            var finalPhase = source.count == 1
            stream.pointee.src_ptr = base
            stream.pointee.src_size = finalPhase ? 1 : source.count - 1
            while true {
                // 상한 + 1을 넘는 출력 칸을 주지 않는다 — 폭탄도 상한 + 1바이트에서 멈춘다
                let room = min(chunkBytes, limit + 1 - output.count)
                let sourceBefore = stream.pointee.src_size
                stream.pointee.dst_ptr = chunk
                stream.pointee.dst_size = room
                let status = compression_stream_process(stream, finalPhase ? finalize : 0)
                let produced = room - stream.pointee.dst_size
                output.append(contentsOf: UnsafeBufferPointer(start: chunk, count: produced))
                if output.count > limit { return .failure(.exceedsLimit) }
                switch status {
                case COMPRESSION_STATUS_END:
                    // 마지막 바이트를 주기 전에 끝났다 = 범위 안에 끝 뒤 바이트가 남았다(다른 독자와 해석이 갈린다)
                    return finalPhase && stream.pointee.src_size == 0 ? .success(output) : .failure(.corrupt)
                case COMPRESSION_STATUS_OK:
                    guard produced == 0, stream.pointee.src_size == sourceBefore else { continue }
                    // 나아가지 못했다 — 앞 단계 입력을 다 썼으면 마지막 1바이트를 마무리로 준다. 그 밖은 멈춘 스트림이라 끝없이 돌지 않게 끊는다
                    // (실측: 잘린 스트림은 마무리 단계에서 이 분기가 아니라 `ERROR`로 온다 — 이 줄은 루프 방지용 방어다. 여기를 지나도 부르는 쪽이
                    // 크기·CRC를 대조한다)
                    guard !finalPhase, stream.pointee.src_size == 0 else { return .failure(.corrupt) }
                    finalPhase = true
                    stream.pointee.src_ptr = base + (source.count - 1)
                    stream.pointee.src_size = 1
                default:
                    return .failure(.corrupt)
                }
            }
        }
    }
}

/// ZIP 엔트리 CRC-32(IEEE 802.3, 다항식 0xEDB88320 반사형) — 해제 결과를 중앙 디렉터리 CRC와 대조한다(6-5a)
enum CRC32 {

    static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
        }
        return value
    }

    static func checksum(_ bytes: [UInt8]) -> UInt32 {
        checksum(bytes[...])
    }

    static func checksum(_ bytes: ArraySlice<UInt8>) -> UInt32 {
        bytes.withUnsafeBufferPointer { buffer in
            table.withUnsafeBufferPointer { table in
                var crc: UInt32 = 0xFFFF_FFFF
                for byte in buffer {
                    crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
                }
                return crc ^ 0xFFFF_FFFF
            }
        }
    }
}
