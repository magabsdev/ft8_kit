#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
FILE="$ROOT/Sources/FT8Decoder/FT8OptimizedDecoder.swift"
TEST_DIR="$ROOT/Tests/FT8DecoderTests"

if [[ ! -f "$FILE" ]]; then
  echo "Cannot find $FILE" >&2
  exit 1
fi

python3 - "$FILE" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

def replace_once(old: str, new: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"Expected one match, found {count}: {old[:120]}")
    text = text.replace(old, new, 1)

replace_once(
'''    public var captureCandidateTraces: Bool

    public init(maximumCandidatesToDecode: Int = 140,''',
'''    public var captureCandidateTraces: Bool
    public var capturePipelineRecords: Bool

    public init(maximumCandidatesToDecode: Int = 140,''')

replace_once(
'''    deduplicationFrequency: Float = 12.5,
    captureCandidateTraces: Bool = false) {''',
'''    deduplicationFrequency: Float = 12.5,
    captureCandidateTraces: Bool = false,
    capturePipelineRecords: Bool = false) {''')

replace_once(
'''        self.captureCandidateTraces = captureCandidateTraces
    }''',
'''        self.captureCandidateTraces = captureCandidateTraces
        self.capturePipelineRecords = capturePipelineRecords
    }''')

replace_once(
'''    public let candidateTraces: [FT8CandidateTrace]

    public init(
        messages: [FT8CompleteDecode],
        metrics: FT8DecodeMetrics,
        candidateTraces: [FT8CandidateTrace] = []
    ) {
        self.messages = messages
        self.metrics = metrics
        self.candidateTraces = candidateTraces
    }''',
'''    public let candidateTraces: [FT8CandidateTrace]
    public let pipelineRecords: [FT8PipelineRecord]

    public init(
        messages: [FT8CompleteDecode],
        metrics: FT8DecodeMetrics,
        candidateTraces: [FT8CandidateTrace] = [],
        pipelineRecords: [FT8PipelineRecord] = []
    ) {
        self.messages = messages
        self.metrics = metrics
        self.candidateTraces = candidateTraces
        self.pipelineRecords = pipelineRecords
    }''')

replace_once(
'''        var decoded: [FT8CompleteDecode] = []
        var candidateTraces: [FT8CandidateTrace] = []
        var retryCandidates:''',
'''        var decoded: [FT8CompleteDecode] = []
        var candidateTraces: [FT8CandidateTrace] = []
        var pipelineRecords: [FT8PipelineRecord] = []
        let pipelineRecorder = FT8PipelineRecorder(extractor: extractor)
        var retryCandidates:''')

replace_once(
'''            let soft = extraction.softSymbols
            softCount += 1

            trace(''',
'''            let soft = extraction.softSymbols
            softCount += 1

            var pipelineRecordIndex: Int?
            if configuration.capturePipelineRecords {
                do {
                    let record = try pipelineRecorder.captureReceivedTones(
                        candidateIndex: index,
                        candidate: candidate,
                        spectrogram: spectrogram
                    )
                    pipelineRecords.append(record)
                    pipelineRecordIndex = pipelineRecords.count - 1
                } catch {
                    trace("[Optimized] Pipeline capture failed: \\(error)")
                }
            }

            trace(''')

replace_once(
'''            guard soft.averageConfidence >= configuration.minimumSoftSymbolConfidence else {
                trace("[Optimized] Soft-symbol confidence below threshold")
                if configuration.captureCandidateTraces {''',
'''            guard soft.averageConfidence >= configuration.minimumSoftSymbolConfidence else {
                trace("[Optimized] Soft-symbol confidence below threshold")
                attachPipelineMessageOutcome(
                    decodedText: nil,
                    confidence: nil,
                    failureReason: "softSymbolConfidenceBelowThreshold",
                    recordIndex: pipelineRecordIndex,
                    records: &pipelineRecords
                )
                if configuration.captureCandidateTraces {''')

replace_once(
'''            let ldpc = try ldpcDecoder.decode(soft)

            trace(''',
'''            let ldpc = try ldpcDecoder.decode(soft)

            if let recordIndex = pipelineRecordIndex {
                pipelineRecords[recordIndex] =
                    FT8PipelineRecorder.attaching(
                        ldpcResult: ldpc,
                        to: pipelineRecords[recordIndex]
                    )
            }

            trace(''')

replace_once(
'''            if let message = primaryMessage,
               !primaryText.isEmpty {
                trace("[Optimized] Message decode returned: \\(message.text)")

                if !configuration.decodeUnsupportedMessages,
                   case .unsupported = message.message {
                    trace("[Optimized] Unsupported message skipped")
                    continue
                }''',
'''            if let message = primaryMessage,
               !primaryText.isEmpty {
                trace("[Optimized] Message decode returned: \\(message.text)")

                if !configuration.decodeUnsupportedMessages,
                   case .unsupported = message.message {
                    trace("[Optimized] Unsupported message skipped")
                    attachPipelineMessageOutcome(
                        decodedText: primaryText,
                        confidence: message.confidence,
                        failureReason: "unsupportedMessageRejected",
                        recordIndex: pipelineRecordIndex,
                        records: &pipelineRecords
                    )
                    continue
                }

                attachPipelineMessageOutcome(
                    decodedText: primaryText,
                    confidence: message.confidence,
                    failureReason: nil,
                    recordIndex: pipelineRecordIndex,
                    records: &pipelineRecords
                )''')

replace_once(
'''                if primaryMessage != nil {
                    trace("[Optimized] Empty decoded message rejected")
                } else {
                    trace("[Optimized] Message decode failed")
                }

                if configuration.captureCandidateTraces {''',
'''                let messageFailure = primaryMessage == nil
                    ? "messageDecodeFailed"
                    : "emptyMessageRejected"

                attachPipelineMessageOutcome(
                    decodedText: primaryText.isEmpty ? nil : primaryText,
                    confidence: primaryMessage?.confidence,
                    failureReason: messageFailure,
                    recordIndex: pipelineRecordIndex,
                    records: &pipelineRecords
                )

                if primaryMessage != nil {
                    trace("[Optimized] Empty decoded message rejected")
                } else {
                    trace("[Optimized] Message decode failed")
                }

                if configuration.captureCandidateTraces {''')

replace_once(
'''            ),
            candidateTraces: candidateTraces
        )
    }

    private func makeTrace(''',
'''            ),
            candidateTraces: candidateTraces,
            pipelineRecords: pipelineRecords
        )
    }

    private func attachPipelineMessageOutcome(
        decodedText: String?,
        confidence: Float?,
        failureReason: String?,
        recordIndex: Int?,
        records: inout [FT8PipelineRecord]
    ) {
        guard let recordIndex,
              records.indices.contains(recordIndex) else {
            return
        }

        records[recordIndex] =
            FT8PipelineRecorder.attachingMessageOutcome(
                decodedText: decodedText,
                confidence: confidence,
                failureReason: failureReason,
                to: records[recordIndex]
            )
    }

    private func makeTrace(''')

path.write_text(text)
PY

mkdir -p "$TEST_DIR"
cat > "$TEST_DIR/FT8OptimizedPipelineCaptureTests.swift" <<'SWIFT'
import XCTest
import FT8Encoder
@testable import FT8Decoder

final class FT8OptimizedPipelineCaptureTests: XCTestCase {
    func testPipelineCaptureIsDisabledByDefault() {
        XCTAssertFalse(
            FT8OptimizedDecoderConfiguration().capturePipelineRecords
        )
    }

    func testGeneratedWaveformProducesCompletePipelineRecord() throws {
        let text = "CQ G0ABC IO91"
        let tones = try FT8Encoder.encode(text: text)
        let waveform = FT8Waveform.generate(
            tones: tones,
            configuration: .init(
                sampleRate: 12_000,
                baseFrequency: 1_000,
                amplitude: 0.95,
                padToSlot: true
            )
        )

        let synchronizer = FT8Synchronizer(
            configuration: .init(
                minimumFrequency: 900,
                maximumFrequency: 1_100,
                frequencyStep: 3.125,
                minimumSyncScore: 0.30,
                minimumSNRDB: 0,
                maximumCandidates: 12,
                estimateDrift: false
            )
        )

        let slotDecoder = FT8SlotDecoder(
            decoder: FT8OptimizedDecoder(
                configuration: .init(
                    maximumCandidatesToDecode: 12,
                    minimumCandidateConfidence: 0,
                    minimumSoftSymbolConfidence: 0,
                    capturePipelineRecords: true
                ),
                synchronizer: synchronizer,
                extractor: SoftSymbolExtractor(
                    configuration: .init(
                        integrationRadius: 1,
                        minimumObservationsPerSymbol: 2,
                        llrScale: 1,
                        llrLimit: 24
                    )
                )
            )
        )

        let batch = try slotDecoder.decode(samples: waveform)

        XCTAssertFalse(batch.pipelineRecords.isEmpty)
        XCTAssertTrue(
            batch.pipelineRecords.allSatisfy(\.isStructurallyValid)
        )

        let successful = batch.pipelineRecords.first {
            $0.decodedText == text
                && $0.failureReason == nil
                && $0.decodedCodeword.count
                    == FT8PipelineRecord.channelBitCount
                && $0.informationBits.count
                    == FT8PipelineRecord.informationBitCount
        }

        XCTAssertNotNil(successful)
        XCTAssertEqual(successful?.parityPassed, true)
        XCTAssertEqual(successful?.crcPassed, true)
        XCTAssertNotNil(successful?.messageConfidence)
    }

    func testBatchInitializerRetainsPipelineRecords() {
        let record = FT8PipelineRecord(
            candidateIndex: 1,
            startTime: 0,
            frequency: 1_000,
            synchronizerScore: 0.8
        )
        let metrics = FT8DecodeMetrics(
            candidatesFound: 0,
            candidatesScheduled: 0,
            softSymbolsExtracted: 0,
            ldpcAttempts: 0,
            parityPassed: 0,
            crcPassed: 0,
            messagesReturned: 0,
            elapsedSeconds: 0
        )

        let batch = FT8DecodeBatch(
            messages: [],
            metrics: metrics,
            pipelineRecords: [record]
        )

        XCTAssertEqual(batch.pipelineRecords, [record])
    }
}
SWIFT

echo "Checkpoint 7.3.1H applied."
echo "Run: ./test.sh"
