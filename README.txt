FT8Kit Checkpoint 7.3.1F — Fixed

Replace these two files:

Sources/FT8Decoder/FT8PipelineRecorder.swift
Tests/FT8DecoderTests/FT8PipelineRecorderTests.swift

Delete this incorrectly added file before testing:

Tests/FT8DecoderTests/FT8PipelineRecorderTests.additions.swift

Then run:

rm -rf .build
swift package clean
swift build --product ft8-validate
swift test
