cd .. && clear && swift build --product ft8-validate && perl -e '
    alarm 60;
    exec @ARGV
' .build/debug/ft8-validate \
  decode \
  --diagnostics \
  --json \
  ft8_lib/test/wav/191111_110130.wav
