import Foundation
import Testing
import PackImport
import TadakData
import TadakDomain

// TadakDataTests에서 옮겨 왔다 — 내 채움글 **쓰기**(`AppGroupUserSnippetStore`)가 앱 전용 모듈 PackImport로 옮겨 가며(codex 반론 #11)
// 왕복 시험도 따라왔다. 읽기는 키보드가 쓰는 TadakData `AppGroupSnippetRepository`로 본다(같은 키 — 두 모듈이 맞물리는지)

@Suite("채움글 저장소")
struct SnippetRepositoryTests {

    @Test("사용자 문구 저장·읽기가 왕복한다")
    func userSnippetsRoundTrip() {
        let suite = "test.tadak.snippets.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let repository = AppGroupSnippetRepository(suiteName: suite)
        let writer = AppGroupUserSnippetStore(suiteName: suite)
        #expect(repository.entries().isEmpty, "저장 전에는 비어 있다")

        let saved = [SnippetEntry(trigger: "우리집", title: "집 주소", body: "서울시 어딘가 123")]
        #expect(writer.save(saved))
        #expect(repository.entries() == saved)
        #expect(writer.entries() == saved)
    }
}
