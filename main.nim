
######################################################################
# Plumbing and avrlibc glue. Interrupt handlers are hooked to
# call into Nim code
######################################################################

{.emit:"""

#include <avr/io.h>
#include <avr/delay.h>
#include <avr/sleep.h>
#include <avr/interrupt.h>

void on_tick(void);
void on_uart_rx(uint8_t c);

void init(void)
{
  // Timer
  TCCR0A = (1<<WGM01) | (1<<WGM00);
  TCCR0B = (1<<CS12) | (1<<CS10);
  TIMSK0 |= (1<<TOIE0);
  // Uart
  uint32_t div = 8;
  UBRR0H = (div >> 8);
  UBRR0L = (div & 0xff);                     
  UCSR0C = (1<<UCSZ01) | (1<<UCSZ00);
  UCSR0B = (1<<RXCIE0) | (1<<RXEN0) | (1<<TXEN0); 
  // Interrupts
  sei();
}

ISR(TIMER0_OVF_vect)
{
  on_tick();
}

ISR(USART_RX_vect)
{
  on_uart_rx(UDR0);
}

void uar_tx(uint8_t c) {
  while (!(UCSR0A & (1 << UDRE0)));
  UDR0 = c;
}

""".}

proc sleep_mode() {.importc: "sleep_mode", nodecl.}
proc init() {.importc: "init", nodecl.}
proc uart_tx(c: uint8) {.importc: "uar_tx", nodecl.}
proc strerror(_: cint): cstring {.exportc.} = ""
proc delay_ms(ms: cdouble) {.importc: "_delay_ms", nodecl.}
proc echo(s: string) = 
  for c in s:
    uart_tx(c.uint8)


######################################################################
# End of plumbing. Start of scheduler and task implementation
######################################################################

import cps

# Define our continuation task type, this holds an enum to indicate
# what to wait for, and how long

type
  Waitfor = enum Timer, Uart
  C = ref object of Continuation
    waitfor: Waitfor
    t_when: uint32

var ticks: uint32 = 0
var tasks: seq[C]
var rx_buf: uint8

# Create a new task and add it to the queue
proc run(c: C) =
  c.t_when = ticks
  tasks.add(c)

template spawn(f: untyped) =
  run whelp f

# Tick ISR handler: find tasks waitig for a timer and resume them
proc on_tick() {.exportc.} =
  for t in tasks.mitems:
    if t.waitfor == Waitfor.Timer:
      if ticks >= t.t_when:
        discard trampoline(t)
  inc ticks

# Uart ISR handler: store the received byte and resume tasks waiting for it
proc on_uart_rx(c: uint8) {.exportc.} =
  rx_buf = c
  for t in tasks.mitems:
    if t.waitfor == Waitfor.Uart:
      discard trampoline(t)

# Sleep until the next timer event
proc sleep(c: C, duration: uint32): C {.cpsMagic.} =
  c.waitfor = Waitfor.Timer
  c.t_when = ticks + duration

# Sleep until the next uart event
proc rx_wait(c: C): C {.cpsMagic.} =
  c.waitfor = Waitfor.Uart

template rx(): char =
  rx_wait()
  rx_buf.char

######################################################################
# End of scheduler: main example program
######################################################################


# This function prints a message every now and then.

proc printer(interval: uint32, msg: string) {.cps:C.} =
  while true:
    echo "tick " & msg & "\n"
    sleep(interval)


# This functions is a minimal line editor that will print
# every line received on the uart

proc reader() {.cps:C.} =

  var line = newString(32)

  while true:
    let c = rx()
    case c
    of '\n', '\r':
      echo "got : " & line & "\n"
      line = ""
    of '\b', 127.char:
      if line.len > 0:
        line.setLen(line.len - 1)
        echo "\b \b"
    else:
      line.add(c)
      echo c


# Main code: intialize the hardware and spawn some tasks

init()
spawn printer(100, "one")
spawn printer(150, "two")
spawn reader()

# The main code does literally nothing, only put the 
# CPU to sleep. Any ISRs will wake it up and resume tasks
# as needed

while true:
  sleep_mode()

