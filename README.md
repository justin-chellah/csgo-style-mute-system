# [ANY] CS:GO-Style Mute System
This is a SourceMod plugin that allows players to mute/unmute other players including their chat messages; it works in the same fashion as CS: GO by also sanitizing player names (replacing it with "Muted Player #<userid>" and hiding their avatars on the scoreboard. This is very handy for dealing with offensive players and was developed with the intent to reduce reports about offensive behavior in my community back in 2021.

Players also remain muted until the muter has either left the server or decided to unmute them. Muted players are also unable to bypass the mute by rejoining or leaving the server and this is achieved by bookkeeping their Steam account ids with every mute.

# Commands
- `sm_selfmute` (or `sm_sm`)
- `sm_selfunmute` (or `sm_su`)

# Requirements
- [SourceMod 1.11+](https://www.sourcemod.net/downloads.php?branch=stable)
- [Chat-Processor](https://github.com/Drixevel-Archive/Chat-Processor)
- [userinfo proxy](https://github.com/shqke/userinfoproxy)

# Supported Platforms
- Windows
- Linux

# Supported Games
- Left 4 Dead 2
- Left 4 Dead