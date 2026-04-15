# SenConnect 2
[SentyTek Website](https://sentytek.github.io/software/senconnect)

## Connected Parties Made Easy
SenConnect simplifies the way you stay connected with other drivers. SenConnect can display the position of other SentyTek vehicles on the dashboard map, giving a social aspect to driving. You can see where your friends are, coordinate meetups, and even share your location for safety purposes. 

![The map showing nearby SentyTek vehicles.](image.png)

Whether you're cruising with friends or just want to see who's out there, SenConnect makes it easy to stay connected on the road. It's a simple way to add a little more fun and connection to your drives. It's even possible to have private parties and secure codes.

# The SenConnect 2 Standard
SenConnect 2 is a remarkably simple standard that allows rich car-2-car communications. It allows sending your position, heading, a color ID, and a name over the network to other vehicles.

Vehicle names occupy channels 7-25 on the Transmitter. With 2 ASCII characters per channel, this allows names up to 36 characters long. To not prevent flooding the display, the SenCar implementation of SenConnect 2 only shows the name when a vehicle pointer is clicked on.

A SenConnect unit starts by sweeping all frequencies in the band and choosing an unoccupied one. It then switches between two states: sweeping the band to collect occupied frequencies, and polling these frequencies to collect vehicle data and publish them to the map. During sweeps, it uses a "stepped sweep", only searching every N frequencies in a given sweep before returning to polling vehicles, then moving to the next lane. E.g. if step is 2, then unit will sweep every odd frequency, poll known vehicles, sweep even frequencies, poll known vehicles, reset known list, poll odd, etc.

## Definitions
- Transmitter - The radio that is set to always transmit mode, which transmits information about the vehicle.
- Scanner - The radio that is not set to transmit, which receives information from other vehicles.

## Transmitter Composite Channels
Numbers:
1. Group ID (Float, any range)
2. Transmitter Frequency (Int, 100..200)
3. X coordinate (Float, any range)
4. Y coordinate (Float, any range)
5. Heading (Float, 0..360)
6. Color ID (Int, 1..7)

7-25. Vehicle name (Ints, ASCII (30..39, 65..90), 2 chars/channel)

26-32. Inop.

## Current Limitations
- Colors can only be one of a few values set from an integer. These colors are the Bright colors from any of the selectable SenCar 6 theme colors. This means variable colors are currently not supported.
- The frequency band is currently frequencies ~100..200.
- It is possible, although rare, for units spawned at the same time to choose the same frequency. This can be solved by resetting one or both units independently.
- Multiplayer desync may make it so one or more units do not show up for some clients when they should.

## The State Machine
SenConnect 2 uses a central state machine to manage itself, controlling modes and what it's doing. A state machine is a computer program that exists in any one of many states at once. The following is a list of states SenConnect 2 uses:
- 0 - Just spawned/reset. Waits 5 ticks before moving to state 1 to let tick delay settle
- 1 - Sweeping entire frequency band and selecting unused frequency
- 2 - Frequency selected and ready to sweep again
- 3 - Sweeping frequency band (potentially using a step) to search for vehicles to poll
- 4 - Polling vehicles rapidly, switching between known frequencies every tick. When tick timer is up, moves to state 3 again.

## Improvements over SenConnect 1
- Compacted into one Lua script with simplified logic
- Uses a state machine architecture for systemic improvements
- Improved transmitting system to reduce issues with tick delay (radio transmits an 'alive' signal and it's own frequency to allow for easier storage)
- Allows transmitting of colors and vehicle names, both are customizable
- Smaller MC footprint (2x2 vs 2x4)
- Since constraints of SW logic system are more well known, SC2 is more effective in sweeping and polling
- Reduced flickering on the map and more consistent vehicle travel
- Generally higher update speeds
- Reduced sweep times by using a stepped sweep. Higher step reduces update time but increase time to unit first detection