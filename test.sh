swift package clean                                                                                                       

swift build --product ft8-validate

swift test
.build/debug/ft8-validate decode --diagnostics --dump-debug /tmp/ft8-trace-checkpoint-2 ft8_lib/test/wav/191111_110130.wav
