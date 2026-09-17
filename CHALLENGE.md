# Challenge: Zephyr in Action

## Build an Interactive Edge Experience with Microchip Hardware and Zephyr RTOS

Build a fun and interactive experience for a trade show booth. It can be a
game, puzzle, installation, demo or short challenge.

Visitors should use real Microchip hardware, see an immediate result and become
curious about Zephyr RTOS. The experience should be easy to understand, fun to
repeat and make people want to discuss how it works.

## Requirements

- Use Microchip hardware with Zephyr RTOS running on the board.
- Include at least one real input and one hardware output.
- Use Zephyr for real functions such as sensors, tasks, timers, events,
  communication or device drivers.
- Provide a graphical interface on the board, a PC, a tablet or in a browser.
- A headless board is allowed. It may communicate with a PC through UART, USB,
  Bluetooth, Wi-Fi, Ethernet or another suitable interface.
- Include a score, result or live leaderboard.
- Make the experience easy to understand, replayable and 1 to 3 minutes long.
- Make the system easy to reset and reliable for many visitors.
- A working prototype is preferred, but a clear concept is sufficient. The
  project does not need to be production-ready.

## Zephyr focus

Zephyr must be part of the real system, not just a name in the documentation.
Show at least two Zephyr concepts through the system or the experience, for
example:

- sensor and device handling
- tasks and timers
- events and message queues
- communication between devices
- hardware drivers
- a PC interface connected to the board

The technical concepts should be part of the interaction where possible. A
separate technical dashboard is optional.

## Visitor experience

- The purpose should be clear within a few seconds.
- A visitor should be able to start without technical help.
- A complete round should take about 1 to 3 minutes.
- A new visitor should be able to start immediately after the previous round.
- The physical hardware should visibly matter to the result.

## Evaluation

- Visitor appeal and fun: 30%
- Use of Microchip hardware: 25%
- Real use of Zephyr RTOS: 25%
- Ease of use and reliability: 10%
- Creativity and discussion potential: 10%

## Example

The repository contains **Flappy Microchip**, a small HDMI game running on the
PIC64GX Curiosity Kit. It uses board buttons as inputs, Zephyr and LVGL for the
application, and an HSS payload for SD-card boot.

It is a reference implementation, not the expected solution. Copy the useful
ideas, ignore the bird and build something people actually want to try.
