
import std/macros
import cps
import glue
import task

proc ticker(interval: uint32, msg: string) {.task.} =
  while true:
    print "tick " & msg & "\n"
    sleep(interval)

# This functions is a minimal line editor that will print
# every line received on the uart

proc reader() {.task.} =

  var line = newString(32)

  while true:
    let c = uart_rx()
    case c
      of 10, 13:
        print "got line: " & line & "\n"
        line.setLen(0)
      of 7, 127:
        if line.len > 0:
          line.setLen(line.len - 1)
          print "\b \b"
      else:
        line.add(c.char)
    print("\r> ")
    print(line)

# Because blinkenligt is important

proc blinker() {.task.} =
  while true:
    set_led(1)
    sleep(100)
    set_led(0)
    sleep(100)

proc uart_reader() {.task.} = 
  while true:
    let c = uart_rx()
    uart_tx(c)
      
# Main code: intialize the hardware and spawn some tasks

init()
spawn uart_reader()
spawn ticker(1000, "one")
spawn ticker(1500, "two")
spawn reader()
spawn blinker()

# The main code does literally nothing, only put the 
# CPU to sleep. Any ISRs will wake it up and resume tasks
# as needed

sei()

while true:
  sleep_mode()

