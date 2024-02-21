
import std/macros
import cps
import glue

type

  EvType = enum Timer, UartRx, UartTx,

  Task* = ref object of Continuation
    case evtype: EvType
      of Timer:
        t_when: uint32
      of UartRx:
        data: uint8
      else:
        discard

# This is the pool of waiting tasks; ideally this would be a set
# instead of a fixed size array, but the set type is too big
var tasks: array[16, Task]

var ticks: uint32 = 0

macro task*(n: untyped): untyped =
  n.addPragma nnkExprColonExpr.newTree(ident"cps", ident"Task")
  n 

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
template spawn*(f: untyped) =
  let t = whelp f
  discard trampoline(t)

# Wait for the given event type
proc waitFor*(t: Task, evType: EvType): Task {.cpsMagic.} =
  suspend t, evType

# Sleep until the next timer event
proc sleep*(t: Task, duration: uint32): Task {.cpsMagic.} =
  t.t_when = ticks + duration
  suspend t, EvType.Timer

# Wait for a uart RX event and return the last received value
proc uart_rx_data*(t: Task): uint8 {.cpsVoodoo} =
  t.data

template uart_rx*(): uint8 =
  waitFor EvType.UartRx
  uart_rx_data()

# Send a byte over the uart
proc uart_tx*(t: Task, c: uint8): Task {.cpsMagic.} =
  suspend t, EvType.UartTx
  uart_tx_byte(c)

proc print*(s: string) {.task.} = 
  var i = 0
  while i < s.len:
    uart_tx(s[i].uint8)
    inc i


