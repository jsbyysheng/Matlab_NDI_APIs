clear
clc

aurora_device = AuroraDriver('COM6');
aurora_device.init();

aurora_device.BEEP(6);
disp(aurora_device.APIREV());

for reply_option = ['0', '4', '5', '7', '8']
    disp(aurora_device.VER(reply_option));
end

aurora_device.detectAndAssignPortHandles();
aurora_device.initPortHandleAll();
aurora_device.enablePortHandleDynamicAll();

aurora_device.startTracking(true);
aurora_device.BEEP(1);

n_samples = 100;
n_tools = aurora_device.n_port_handles;

frames = zeros(n_samples, n_tools);
trans = zeros(n_samples, n_tools, 3);
rots = zeros(n_samples, n_tools, 4);
e = zeros(n_samples, n_tools);

for sample = 1:n_samples
    aurora_device.updateSensorDataAll();
    for tool = 1:n_tools
        ph = aurora_device.port_handles(1, tool);

        trans(sample, tool, 1) = ph.trans(1);
        trans(sample, tool, 2) = ph.trans(2);
        trans(sample, tool, 3) = ph.trans(3);

        rots(sample, tool, 1) = ph.rot(1);
        rots(sample, tool, 2) = ph.rot(2);
        rots(sample, tool, 3) = ph.rot(3);
        rots(sample, tool, 4) = ph.rot(4);

        e(sample, tool) = ph.error;
        frames(sample, tool) = ph.frame_number;
    end
end

aurora_device.stopTracking();
delete(aurora_device);