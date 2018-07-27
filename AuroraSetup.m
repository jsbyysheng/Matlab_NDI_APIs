aurora_device = AuroraDriver('/dev/tty.usbserial-00005414');
serial_present = instrfind;

if(~isempty(serial_present)) 
    
    aurora_device.openSerialPort();
    aurora_device.init();
    aurora_device.setBaudRate(115200);
    aurora_device.detectAndAssignPortHandles();
    aurora_device.initPortHandleAll();
    aurora_device.enablePortHandleDynamicAll();
    aurora_device.startTracking(true); % fast
    aurora_device.BEEP('1');
    fn = zeros(100,2);
    e = zeros(100,2);
    tt = tic;
    for I=1:size(fn,1)
        aurora_device.updateSensorDataAll();
        for S=1:2
            ph = aurora_device.port_handles(1,S);
            %ph.trans
            %ph.rot
            e(I,S)=ph.error;
            fn(I,S) = ph.frame_number;
        end
    end
    to = toc;
    aurora_device.stopTracking();
    aurora_device.port_handles
    delete(aurora_device);
    diff(fn)
    to
end
