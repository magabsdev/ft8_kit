
// Add these tests to FT8PipelineRecorderTests.swift.

func testHardDecisionsUseEstablishedLLRSignConvention() throws {
    let llrs: [Float] = [
        9, -9, 0, -0.25
    ] + Array(repeating: Float(1), count: 170)

    let bits = try FT8PipelineRecorder.hardDecisions(from: llrs)

    XCTAssertEqual(Array(bits.prefix(4)), [0, 1, 0, 1])
    XCTAssertEqual(bits.count, 174)
}

func testHardDecisionsAcceptEmptyIncrementalStage() throws {
    XCTAssertEqual(
        try FT8PipelineRecorder.hardDecisions(from: []),
        []
    )
}

func testHardDecisionsRejectWrongLLRCount() {
    XCTAssertThrowsError(
        try FT8PipelineRecorder.hardDecisions(
            from: Array(repeating: Float.zero, count: 173)
        )
    ) { error in
        XCTAssertEqual(
            error as? FT8PipelineRecorderError,
            .invalidLLRCount(actual: 173)
        )
    }
}

func testHardDecisionsRejectNonFiniteLLR() {
    var llrs = Array(repeating: Float.zero, count: 174)
    llrs[12] = .infinity

    XCTAssertThrowsError(
        try FT8PipelineRecorder.hardDecisions(from: llrs)
    ) { error in
        XCTAssertEqual(
            error as? FT8PipelineRecorderError,
            .nonFiniteLLR(index: 12)
        )
    }
}

func testCaptureStoresExactLLRVectorAndHardDecisions() throws {
    let candidate = makeCandidate()
    let llrs: [Float] = (0..<174).map {
        $0.isMultiple(of: 2) ? Float(8) : Float(-8)
    }

    let record = try FT8PipelineRecorder().captureReceivedTones(
        candidateIndex: 3,
        candidate: candidate,
        toneMetrics: makeToneMetrics(),
        logLikelihoodRatios: llrs
    )

    XCTAssertEqual(record.logLikelihoodRatios, llrs)
    XCTAssertEqual(record.interleavedBits.count, 174)
    XCTAssertEqual(
        record.interleavedBits,
        llrs.map { $0 < 0 ? UInt8(1) : UInt8(0) }
    )
    XCTAssertTrue(record.isStructurallyValid)
}
