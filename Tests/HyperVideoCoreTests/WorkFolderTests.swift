import Foundation
import Testing
@testable import HyperVideoCore

@Suite("Work folder naming")
struct WorkFolderTests {
    @Test func nameCarriesJobID() throws {
        let id = UUID()
        let name = WorkFolder.name(jobID: id)
        let prefix = ".hypervideo-\(id.uuidString)-"
        #expect(name.hasPrefix(prefix))
        #expect(UUID(uuidString: String(name.dropFirst(prefix.count))) != nil)
    }

    @Test func jobIDParsesBackFromName() {
        let id = UUID()
        #expect(WorkFolder.jobID(fromName: WorkFolder.name(jobID: id)) == id)
    }

    @Test func legacyAndUnrelatedNamesHaveNoJobID() {
        #expect(WorkFolder.jobID(fromName: ".hypervideo-\(UUID().uuidString)") == nil)
        #expect(WorkFolder.jobID(fromName: "keep.mp4") == nil)
        #expect(WorkFolder.jobID(fromName: ".hypervideo-\(UUID().uuidString)-junk") == nil)
    }

    @Test func recognisesNewAndLegacyFolders() {
        #expect(WorkFolder.isWorkFolder(name: WorkFolder.name(jobID: UUID())))
        #expect(WorkFolder.isWorkFolder(name: ".hypervideo-\(UUID().uuidString)"))
        #expect(!WorkFolder.isWorkFolder(name: "keep.mp4"))
    }

    @Test func nilJobIDYieldsLegacyShape() {
        let name = WorkFolder.name(jobID: nil)
        #expect(name.hasPrefix(WorkFolder.prefix))
        #expect(UUID(uuidString: String(name.dropFirst(WorkFolder.prefix.count))) != nil)
    }
}
