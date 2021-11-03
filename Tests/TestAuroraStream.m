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

hImage = figure;
hImage.UserData = {{}, {}, {}, {}, {}};
ptr_sample = 0;

aurora_device.configureStreamSensorDataAll(1, @streamModeCallbackFcn, hImage);
pause(1);
aurora_device.configureStreamSensorDataAll(0);

aurora_device.stopTracking();
delete(aurora_device);

function streamModeCallbackFcn(data, hImage)
    ptr_sample = length(hImage.UserData{1}) + 1;
    hImage.UserData{1}{ptr_sample} = data.ts;
    hImage.UserData{2}{ptr_sample} = data.trans;
    hImage.UserData{3}{ptr_sample} = data.rots;
    hImage.UserData{4}{ptr_sample} = data.frames;
    hImage.UserData{5}{ptr_sample} = data.e;
end
