## How it works

This control module manages request and completion queues for SPI-based communication. It includes:
- Request queue for incoming commands
- Completion queue for completed operations
- SPI for communication
- AES and SHA FSM controllers for cryptographic operations
- Bus arbiter for managing multi-source requests

## How to test

- Run `make` in the test/ directory to execute all cocotb tests
- Tests verify queue operations, SPI communication, and FSM functionality
- Results are output to test/results.xml

## External hardware

SPI Master/Host device for sending commands and receiving responses over MOSI/MISO lines
