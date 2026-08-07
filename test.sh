rm -rf .build
swift package clean
swift build --product ft8-validate
swift test

#.build/debug/ft8-validate decode --diagnostics --audit-dir ~/Downloads/ft8-audit ft8_lib/test/wav/191111_110130.wav
#.build/debug/ft8-validate decode --diagnostics --audit-dir ~/Downloads/ft8-audit-7-2 --expected-message "CQ R7IW LN35" --expected-message "CQ TA6CQ KN70" ft8_lib/test/wav/191111_110130.wav


