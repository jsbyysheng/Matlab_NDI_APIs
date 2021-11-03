# Matlab_NDI_APIs

This repository is based on [APIs-NDI-Digital](https://github.com/lara-unb/APIs-NDI-Digital). The original repo contains the necessary libraries for using both the Polaris optical and Aurora electromagnetic tracking systems, from NDI Medical, in Matlab. Both devices use the PortHandle.m file, but otherwise, Aurora and Polaris files are independent. 

In order to use matlab doing ultrasonic IGS, I apply some changes to `Aurora_Driver.m`:
- Update `serial`, which is marked as deprecation,  to `serialport`.
- Add hardware reset device for stable usage.
- Automatically choose the maximum communication baudrate.
- Add stream mode for non-block usage.