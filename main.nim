
######################################################################
# Plumbing and avrlibc glue. Interrupt handlers are hooked to
# call into Nim code
######################################################################

{.emit:"""

#include <avr/io.h>
#include <avr/delay.h>
#include <avr/sleep.h>
#include <avr/interrupt.h>

uint8_t tx_byte = 0;

void isr_timer(void);
void isr_uart_rx(uint8_t c);

void init(void)
{
  // GPIO
  DDRB = (1<<PB5);
  // Timer
  TCCR0A = (1<<WGM01) | (1<<WGM00);
  TCCR0B = (1<<CS11) | (1<<CS10);
  TIMSK0 |= (1<<TOIE0);
  // UART
  uint32_t div = (16000000 / 9600) / 16 - 1;
  UBRR0H = (div >> 8);
  UBRR0L = (div & 0xff);                     
  UCSR0C = (1<<UCSZ01) | (1<<UCSZ00);
  UCSR0B = (1<<RXCIE0) | (1<<RXEN0) | (1<<TXEN0); 
}

ISR(TIMER0_OVF_vect)
{
  isr_timer();
}

ISR(USART_RX_vect)
{
  isr_uart_rx(UDR0);
}

ISR(USART_UDRE_vect)
{
  UDR0 = tx_byte;
  UCSR0B &= ~(1 << UDRIE0);
  isr_uart_udre();
}

void uart_tx_byte(uint8_t c)
{
  tx_byte = c;
  UCSR0B |= (1<<UDRIE0);
}

void set_led(uint8_t on)
{
  if(on)
    PORTB |= (1<<PB5);
  else
    PORTB &= ~(1<<PB5);
}

""".}

proc strerror(_: cint): cstring {.exportc.} = ""

proc sleep_mode() {.importc, nodecl.}
proc init() {.importc, nodecl.}
proc uart_tx_byte(c: uint8) {.importc, nodecl.}
proc set_led(on: uint8) {.importc, nodecl.}
proc sei() {.importc, nodecl.}


######################################################################
# End of plumbing. Start of scheduler and task implementation
######################################################################

import cps
import macros

type

  EvType = enum Timer, UartRx, UartTx,

  Task = ref object of Continuation
    case evtype: EvType
      of Timer:
        t_when: uint32
      of UartRx:
        data: uint8
      else:
        discard

macro task*(n: untyped): untyped =
  n.addPragma nnkExprColonExpr.newTree(ident"cps", ident"Task")
  n 

var tasks: array[8, Task] # I'd rather use a Set[] but these are too big
var ticks: uint32 = 0 # Global time counter

# Find a free slot and add a task to the pool
proc suspend(t: Task, evType: EvType) =
  t.evType = evType
  for i in 0..tasks.high:
    if tasks[i] == nil:
      tasks[i] = t
      return

# Find the given task in the pool; remove it and resume
proc resume(t: Task) =
  for i in 0..tasks.high:
    if tasks[i] == t:
      tasks[i] = nil
      discard trampoline(t)

# Tick ISR handler: find tasks waiting for a timer and resume them
proc isr_timer() {.exportc.} =
  for t in tasks:
    if t != nil and t.evtype == Timer and ticks >= t.t_when:
      t.resume
  inc ticks

# UART rx ISR handler: store the received byte and resume tasks waiting for it
proc isr_uart_rx(c: uint8) {.exportc.} =
  for t in tasks:
    if t != nil and t.evtype == UartRx:
      t.data = c
      t.resume

# UART tx-register-empty ISR handler
proc isr_uart_udre() {.exportc.} =
  for t in tasks:
    if t != nil and t.evtype == UartTx:
      t.resume

######################################################################
# scheduler user facing API
######################################################################

# Create a new task and add start it
template spawn(f: untyped) =
  let t = whelp f
  discard trampoline(t)

# Wait for the given event type
proc waitFor(t: Task, evType: EvType): Task {.cpsMagic.} =
  suspend t, evType

# Sleep until the next timer event
proc sleep(t: Task, duration: uint32): Task {.cpsMagic.} =
  t.t_when = ticks + duration
  suspend t, EvType.Timer

# Wait for a uart RX event and return the last received value
proc uart_rx_data(t: Task): uint8 {.cpsVoodoo} =
  t.data

template uart_rx(): uint8 =
  waitFor EvType.UartRx
  uart_rx_data()

# Send a byte over the uart
proc uart_tx(t: Task, c: uint8): Task {.cpsMagic.} =
  suspend t, EvType.UartTx
  uart_tx_byte(c)

proc print(s: string) {.task.} = 
  var i = 0
  while i < s.len:
    uart_tx(s[i].uint8)
    inc i

######################################################################
# End of scheduler: main example program
######################################################################

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
        line = ""
      of 7, 127:
        if line.len > 0:
          line.setLen(line.len - 1)
          print "\b \b"
      else:
        line.add(c.char)
        uart_tx(c)

# Because blinkenligt is important

proc blinker() {.task.} =
  while true:
    set_led(1)
    sleep(100)
    set_led(0)
    sleep(100)

# Main code: intialize the hardware and spawn some tasks

init()
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

