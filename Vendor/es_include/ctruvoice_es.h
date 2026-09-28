/* Anchor for the CTruVoiceES umbrella modulemap, which SwiftPM requires to
 * be its own directory: sharing upstream/include with CTruVoice makes both
 * umbrellas cover one directory and fails the build. Nothing imports this
 * target from Swift (the link to CTruVoice is at object level); the Spanish
 * sources get their real headers through the target's search paths. */
