
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

proc init*() {.importc, nodecl.}
proc uart_tx_byte*(c: uint8) {.importc, nodecl.}
proc set_led*(on: uint8) {.importc, nodecl.}


proc sleep_mode*() {.header: "avr/sleep.h", importc.}
proc sei*() {.header: "avr/interrupt.h", importc.}

