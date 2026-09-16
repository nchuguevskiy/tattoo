# tattoo demo: /tattoo, /compact, then Claude still knows the decisions.
#
# Real session, real output. Long waits (writing the tattoo, compaction) are cut
# with Hide/Show; nothing on screen is typed except the user's input.
#
#   assets/demo-setup.sh            # fake repo + pre-built session, writes /tmp/demo-env.sh
#   assets/demo-setup.sh --render   # runs this tape, assembles assets/demo.gif
#   assets/demo-setup.sh --cleanup
#
# vhs writes raw frames (Output below); demo-setup.sh --render turns them into the GIF.

Output "/tmp/demo-frames/"

Set Shell bash
Set FontSize 17
Set Width 1200
Set Height 700
Set Padding 20
Set Theme "GitHub Dark"
Set Framerate 20
Set TypingSpeed 40ms
Set WaitTimeout 300s
Set WaitPattern /\$ $/

Hide
Type "source /tmp/demo-env.sh && cd /tmp/billing-api && clear"
Enter
Sleep 1s
Show

Sleep 500ms
Type "claude --resume $SID --plugin-dir /tmp/tattoo"
Sleep 600ms

# Startup (the welcome header) is not recorded; the resumed history pushes it off screen.
Hide
Enter
Wait+Screen@60s /shift\+tab to cycle/
Sleep 4s
Show
Sleep 3s

# 1. Tattoo the session.
Type "/tattoo"
Sleep 700ms
Enter
Sleep 2.5s
Hide
Wait+Screen@240s /(?s)tattoo:tattoo.*· done/
Sleep 500ms
Show
Sleep 4.5s

# 2. Compact.
Type "/compact"
Sleep 600ms
Enter
Sleep 2s
Hide
Wait+Screen@300s /Compacted/
Sleep 1.5s
Show
Sleep 2.5s

# 3. Ask about what the summary usually loses.
Type "Where do we keep idempotency keys, and what did we rule out?"
Sleep 500ms
Enter
Sleep 1s
Hide
Wait+Screen@120s /(?s)rule out\?.*· done/
Show
Sleep 5s

Type "Can I push this to main?"
Sleep 500ms
Enter
Sleep 1s
Hide
Wait+Screen@120s /(?s)to main\?.*· done/
Show
Sleep 5s
