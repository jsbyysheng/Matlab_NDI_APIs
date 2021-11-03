classdef AuroraDriver < handle

    %
    % This class offers a collection of tools used in the command and
    % comunication of NDI Medical electromagnetic tracking system.
    %
    % obj = AuroraDriver('$PATH$') creates an object linking to the device
    % connected to the port specified by the user in '$PATH$'
    %
    % Specific functions are then called using obj.method_name(argument1,...)
    %
    % OBS: All functions that communicate with the Aurora SCU may fail.
    % Command errors may be detected by checking the responded error code.
    % Communication errors may be detected by checking the CRC of the
    % obtained reply. In the current version of this driver none of these
    % error checkings has been implemented.

    % Author: André Augusto Geraldes
    % Email: andregeraldes@lara.unb.br
    % July 2015; Last revision: March 2016

    % Constants
    properties (Constant)

        % Formats for sending commands (source: Aurora_API_Guide page 4)
        COMMAND_FORMAT_1 = 1;
        COMMAND_FORMAT_2 = 2;

        % Sensor reading options (source: Aurora_API_Guide page 12)
        READ_OUT_OF_VOLUME_NOT_ALLOWED = '0001';
        READ_OUT_OF_VOLUME_ALLOWED = '0801';

        % Handle Status (source: Aurora_API_Guide page 13)
        SENSOR_STATUS_VALID = '01';
        SENSOR_STATUS_MISSING = '02';
        SENSOR_STATUS_DISABLED = '04';

        % Baud rate options (source: Aurora_API_Guide page 16)
        BAUD_9600 = '0';
        BAUD_14400 = '1';
        BAUD_19200 = '2';
        BAUD_38400 = '3';
        BAUD_57600 = '4';
        BAUD_115200 = '5';
        BAUD_921600 = '6';
        BAUD_230400 = 'A';

        % Tool tracking priority codes (source: Aurora_API_Guide page 26)
        TT_PRIORITY_STATIC = 'S';
        TT_PRIORITY_DYNAMIC = 'D';
        TT_PRIORITY_BUTTON = 'B';

        % PHSR Reply options (source: Aurora_API_Guide page 33)
        PHSR_HANDLES_ALL = '00';
        PHSR_HANDLES_TO_BE_FREED = '01';
        PHSR_HANDLES_OCCUPIED = '02';
        PHSR_HANDLES_OCCUPIED_AND_INITIALIZED = '03';
        PHSR_HANDLES_ENABLED = '04';

        % Reset options
        RESET_SOFT = '0';
        RESET_HARD = '1';

        % Tracking mode options (source: Aurora_API_Guide page 59)
        TRACKING_OPTION_NONE = '';
        TRACKING_OPTION_FAST_MODE = '40';
        TRACKING_OPTION_RESET_COUNTER = '80';
        TRACKING_OPTION_FAST_MODE_RESET_COUNTER = 'C0';

    end

    properties (GetAccess = public, SetAccess = private)

        % Member variables
        serial_port_name; % Serial port name
        serial_port; % Serial port object
        n_port_handles; % Number of existing port handles
        port_handles; % Array of port handle objects

        % Global parameters
        selected_command_format;

        % State variables
        device_init;

        streamModeCallbackFcn;
        streamStartStopFlag = 0;
        hImage;
    end

    % Public methods
    methods (Access = public)

        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %             CONSTRUCTOR              %
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        function obj = AuroraDriver(serial_port_name)
            obj.serial_port_name = serial_port_name;

            obj.n_port_handles = 0;
            obj.selected_command_format = obj.COMMAND_FORMAT_2;
            obj.device_init = 0;
        end

        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %             Reset Device             %
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        function reset_AuroraDevice(obj)
            s = serial(obj.serial_port_name);
            obj.oldAPI_openSerialPort(s);
            serialbreak(s, 10);
            serialbreak(s, 10);
            obj.oldAPI_closeSerialPort(s);
        end

        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %    OLD API SERIAL COMM FUNCTIONS     %
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        function oldAPI_openSerialPort(~, s)

            if (strcmp(s.Status, 'closed'))
                fopen(s);
            end

        end

        function oldAPI_closeSerialPort(~, s)

            if (strcmp(s.Status, 'open'))
                fclose(s);
            end

        end

        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %         DEVICE CONFIGURATION         %
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

        function ret = init(obj)
            %
            % init()
            %
            % Initiate the Aurora SCU. This needs to be performed right after
            % opening the serial port, for enabling all other functions.
            obj.reset_AuroraDevice()

            obj.serial_port = serialport(obj.serial_port_name, 9600, "Timeout", 10);
            configureTerminator(obj.serial_port, "CR");
            obj.serial_port.ByteOrder = 'little-endian';

            flush(obj.serial_port);

            if obj.setBaudRate() ~= 1
                ret = 0;
                return
            end

            obj.INIT();
            obj.device_init = 1;
            ret = 1;
        end

        function startTracking(obj, dofast)
            %
            % startTracking()
            %
            % Puts the Aurora SCU into Tracking mode. This enables the position
            % reading functions, but disables configuration functions. For
            % further information, reffer to the Aurora_API_Guide page 3
            if nargin == 1
                dofast = 0;
            end

            if dofast
                p = obj.TRACKING_OPTION_FAST_MODE_RESET_COUNTER;
            else
                p = obj.TRACKING_OPTION_RESET_COUNTER;
            end

            obj.TSTART(p);
        end

        function stopTracking(obj)
            %
            % stopTracking()
            %
            % Puts the Aurora SCU back into Setup mode
            obj.TSTOP();
        end

        function detectAndAssignPortHandles(obj)
            %
            % detectAndAssignPortHandles()
            %
            % Retrieves the list of all available Port Handles, with their ID
            % and Status, and initialize the port_handles member variable
            reply = obj.PHSR(obj.PHSR_HANDLES_ALL);
            obj.n_port_handles = hex2dec(reply(1:2));

            for i_port_handle = 1:obj.n_port_handles
                s = 3 + 5 * (i_port_handle - 1);
                id = reply(s:s + 1);
                status = reply(s + 2:s + 4);

                if (i_port_handle == 1)
                    obj.port_handles = PortHandle(id, status);
                else
                    obj.port_handles(1, i_port_handle) = PortHandle(id, status);
                end

            end

        end

        function updatePortHandleStatusAll(obj)
            %
            % updatePortHandleStatusAll()
            %
            % Query the Aurora SCU for the current status of all available Port
            % Handles and updates the Port Handle objects that have already been
            % detected.
            reply = obj.PHSR(obj.PHSR_HANDLES_ALL);
            n_found_port_handles = hex2dec(reply(1:2));

            for i_found_port_handle = 1:n_found_port_handles
                s = 3 + 5 * (i_found_port_handle - 1);
                id = reply(s:s + 1);
                status = reply(s + 2:s + 4);

                for i_port_handle = 1:obj.n_port_handles

                    if (strcmp(obj.port_handles(1, i_port_handle).id, id))
                        obj.port_handles(1, i_port_handle).updateStatus(status);
                        break;
                    end

                end

            end

        end

        function initPortHandle(obj, port_handle_id)
            %
            % initPortHandle(port_handle_id)
            %
            % Init one Port Handle
            obj.PINIT(port_handle_id);
        end

        function initPortHandleAll(obj)
            %
            % initPortHandleAll()
            %
            % Init all Port Handles that have already been detected and update
            % their status
            for i_port_handle = 1:obj.n_port_handles
                obj.initPortHandle(obj.port_handles(1, i_port_handle).id);
            end

            obj.updatePortHandleStatusAll();
        end

        function enablePortHandleDynamic(obj, port_handle_id)
            %
            % enablePortHandleDynamic(port_handle_id)
            %
            % Enable one Port Handle
            obj.PENA(port_handle_id, obj.TT_PRIORITY_DYNAMIC);
        end

        function enablePortHandleDynamicAll(obj)
            %
            % enablePortHandleDynamicAll()
            %
            % Enable all Port Handles that have already been detected and
            % update their status
            for i_port_handle = 1:obj.n_port_handles
                obj.enablePortHandleDynamic(obj.port_handles(1, i_port_handle).id);
            end

            obj.updatePortHandleStatusAll();
        end

        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %            SENSOR READING            %
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

        function readSensorDataFrame(obj)
            % Error checking information
            start_sequence = read(obj.serial_port, 1, 'uint16');
            reply_length = read(obj.serial_port, 1, 'uint16');
            header_CRC = read(obj.serial_port, 1, 'uint16');

            % Number of available Port Handles
            num_handle_reads = read(obj.serial_port, 1, 'uint8');

            for i_handle_reads = 1:num_handle_reads

                % Get the Port Handle ID as a 2 character hexadecimal
                handle_id = dec2hex(read(obj.serial_port, 1, 'uint8'), 2);

                % Get the Port Handle status as a 2 character hexadecimal
                sensor_status = dec2hex(read(obj.serial_port, 1, 'uint8'), 2);

                % Locate the index of the current handle in the
                % port_handles object array and update the sensor status
                handle_index = 1;

                for i_port_handle = 1:obj.n_port_handles

                    if (strcmp(obj.port_handles(1, i_port_handle).id, handle_id))
                        handle_index = i_port_handle;
                        obj.port_handles(1, handle_index).updateSensorStatus(sensor_status);
                        break;
                    end

                end

                % If the port is not disabled, read sensor data
                if (strcmp(sensor_status, obj.SENSOR_STATUS_DISABLED) == 0)

                    % If the sensor status is valid, read its translation
                    % and rotation data
                    if (strcmp(sensor_status, obj.SENSOR_STATUS_VALID))
                        q0 = read(obj.serial_port, 1, 'single');
                        qX = read(obj.serial_port, 1, 'single');
                        qY = read(obj.serial_port, 1, 'single');
                        qZ = read(obj.serial_port, 1, 'single');
                        rot = [q0 qX qY qZ];

                        tX = read(obj.serial_port, 1, 'single');
                        tY = read(obj.serial_port, 1, 'single');
                        tZ = read(obj.serial_port, 1, 'single');
                        trans = [tX tY tZ];

                        error = read(obj.serial_port, 1, 'single');

                        % Update the translation and rotation of the
                        % corresponding Port Handle object
                        obj.port_handles(1, handle_index).updateTrans(trans);
                        obj.port_handles(1, handle_index).updateRot(rot);
                        obj.port_handles(1, handle_index).updateError(error);
                    end

                    % Read the handle status and frame number
                    handle_status = dec2hex(read(obj.serial_port, 1, 'uint32'), 8);
                    frame_number = read(obj.serial_port, 1, 'uint32');

                    % Update the status and frame_number of the
                    % corresponding Port Handle object
                    obj.port_handles(1, handle_index).updateStatusComplete(handle_status);
                    obj.port_handles(1, handle_index).updateFrameNumber(frame_number);

                end

            end

            % More error checking information
            system_status = read(obj.serial_port, 1, 'uint16');
            crc = read(obj.serial_port, 1, 'uint16');
        end

        function configureStreamSensorDataAll(obj, varargin)
            % enable, streamModeCallbackFcn, hImage
            try
                narginchk(2, 4);
            catch
                throwAsCaller(MException("Aurora:serialport", 'configureStreamSensorDataAll:IncorrectInputArgumentsPlural'));
            end

            if (varargin{1} == 1)
                disp("configureStreamSensorDataAll: enable");
                obj.hImage = varargin{3};
                obj.streamModeCallbackFcn = varargin{2};
                configureCallback(obj.serial_port, "byte", 2, @obj.streamSensorDataAll);

                if (obj.device_init == 1)
                    % Send a BX command for reading all sensors
                    obj.sendCommand(sprintf('BX %s', obj.READ_OUT_OF_VOLUME_ALLOWED));
                    obj.streamStartStopFlag = 1;
                else
                    disp('Device is not init!!!');
                    configureCallback(obj.serial_port, "off");
                    obj.streamStartStopFlag = 0;
                end

            else
                disp("configureStreamSensorDataAll: disable");
                obj.streamStartStopFlag = 0;
            end

        end

        function streamSensorDataAll(obj, ~, ~)

            if obj.streamStartStopFlag == 1

                try
                    obj.readSensorDataFrame();
                    n_tools = obj.n_port_handles;

                    ts = Utility.getCurrentUnixTimeStamp();
                    trans = zeros(n_tools, 3);
                    rots = zeros(n_tools, 4);
                    frames = zeros(n_tools);
                    e = zeros(n_tools);

                    for tool = 1:n_tools
                        ph = obj.port_handles(1, tool);

                        trans(tool, 1) = ph.trans(1);
                        trans(tool, 2) = ph.trans(2);
                        trans(tool, 3) = ph.trans(3);

                        rots(tool, 1) = ph.rot(1);
                        rots(tool, 2) = ph.rot(2);
                        rots(tool, 3) = ph.rot(3);
                        rots(tool, 4) = ph.rot(4);

                        e(tool) = ph.error;

                        frames(tool) = ph.frame_number;
                    end

                    data.ts = ts;
                    data.trans = trans;
                    data.rots = rots;
                    data.frames = frames;
                    data.e = e;

                    obj.streamModeCallbackFcn(data, obj.hImage);
                catch
                    disp('Error Read Aurora Sensor Data!');
                end

                flush(obj.serial_port);
                obj.sendCommand(sprintf('BX %s', obj.READ_OUT_OF_VOLUME_ALLOWED));

            else
                configureCallback(obj.serial_port, "off");
                flush(obj.serial_port);
            end

        end

        function updateSensorDataAll(obj)
            %
            % updateSensorDataAll()
            %
            % Reads the current measurement of all sensors and update the
            % corresponding Port Handle objects.

            if (obj.device_init == 1)

                % Send a BX command for reading all sensors
                obj.sendCommand(sprintf('BX %s', obj.READ_OUT_OF_VOLUME_ALLOWED));
                obj.readSensorDataFrame();
            end

        end

        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %     NEEDLE SPECIFIC FUNCTIONS        %
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

        function status = readSensorStatus(obj)
            obj.updateSensorDataAll();
            status = obj.port_handles(1, 1).sensor_status;
        end

        function [angle, error] = measureTipOrientation(obj)
            obj.updateSensorDataAll();
            rot = obj.port_handles(1, 1).rot;
            [RX, RY, RZ] = quat2angle(rot);
            angle = RY;
            error = obj.port_handles(1, 1).error;
        end

        function error = getError(obj)
            obj.updateSensorDataAll();
            status = obj.port_handles(1, 1).sensor_status;
            error = obj.port_handles(1, 1).error;

            if (strcmp(status, obj.SENSOR_STATUS_MISSING) || strcmp(status, obj.SENSOR_STATUS_DISABLED))
                error = 99;
            end

        end

        function sensor_available = isSensorAvailable(obj)

            if (obj.device_init == 1)
                obj.updateSensorDataAll();
                status = obj.port_handles(1, 1).sensor_status;

                if (strcmp(status, obj.SENSOR_STATUS_MISSING) || strcmp(status, obj.SENSOR_STATUS_DISABLED))
                    sensor_available = 0;
                else
                    sensor_available = 1;
                end

            else
                sensor_available = 0;
            end

        end

    end

    % Private methods
    methods (Access = public)

        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %    SERIAL COMM AUXILIAR FUNCTIONS    %
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

        function sendCommand(obj, command)
            %
            % sendCommand(command)
            %
            % This function receives a command as an entire formated string and
            % sends it to the Aurora SCU. There are two formats for sending
            % commands. Format 2 contains only the command, in string format.
            % Format 1 contains also a CRC for error checking. For more
            % information on that, check the Aurora_API_Guide page 4
            if (obj.selected_command_format == obj.COMMAND_FORMAT_1)
                % Option not implemented
                % Format 1 should replace the ' ' character in the command
                % string per a ':' character and append a CRC to the end of
                % the command.
                error('format 1 with CRC not implemented');
            else
                writeline(obj.serial_port, command);
            end

        end

        function reply = sendCommandAndGetReply(obj, command)
            obj.sendCommand(command);
            reply = char(readline(obj.serial_port));
        end

        function ret = setBaudRate(obj)
            % setBaudRate(baud_rate)
            %
            % This function allows setting the Baud Rate of the serial port,
            % but it assumes all the other configurations of the port are:
            %   - Data bits = 8 bits
            %   - Parity = None
            %   - Stop bits = 1 bit
            %   - Hardware handshaking = OFF
            %
            % If any of these settings needs changing, this function must be
            % modified.
            %
            % For further information on the serial port parameters, reffer to
            % the Aurora_API_Guide page 16
            for baud_rate = [921600, 230400, 115200, 57600, 38400, 19200, 14400, 9600]

                switch baud_rate
                    case 9600
                        baud_rate_code = obj.BAUD_9600;
                    case 14400
                        baud_rate_code = obj.BAUD_14400;
                    case 19200
                        baud_rate_code = obj.BAUD_19200;
                    case 38400
                        baud_rate_code = obj.BAUD_38400;
                    case 57600
                        baud_rate_code = obj.BAUD_57600;
                    case 115200
                        baud_rate_code = obj.BAUD_115200;
                    case 921600
                        baud_rate_code = obj.BAUD_921600;
                    case 230400
                        baud_rate_code = obj.BAUD_230400;
                    otherwise
                        fprintf('ERROR AuroraDriver::setBaudRate - Invalid baud rate %d\n', baud_rate);
                        return
                end

                if string(obj.COMM(baud_rate_code, '0', '0', '0', '1')).startsWith("OKAY")
                    setRTS(obj.serial_port, true);
                    setDTR(obj.serial_port, true);
                    obj.serial_port.BaudRate = baud_rate;
                    ret = 1;
                    return
                end

            end

            ret = 0;
        end

        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %            API COMMANDS              %
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

        % Implement the serial communication for all the API commands.
        % Since all these functions are private, the arguments are never
        % verified. They are assumed to be already verified by the caller.

        % The replies are returned integrally and are supposed to be
        % treated by the caller function.

        % OBS: Matlab automatically adds the 'CR' character at the end of
        % every message sent through the serial. For that reason, you
        % should never append a 'CR' to the end of the commands.

        function reply = APIREV(obj)
            reply = obj.sendCommandAndGetReply('APIREV ');
        end

        function reply = BEEP(obj, n_beep)
            reply = obj.sendCommandAndGetReply(sprintf('BEEP %d', n_beep));
        end

        function [reply_body, error_checking] = BX(obj, reply_option)
            obj.sendCommand(sprintf('BX %s', reply_option));

            start_sequence = read(obj.serial_port, 1, 'uint16');
            reply_length = read(obj.serial_port, 1, 'uint16');
            header_CRC = read(obj.serial_port, 1, 'uint16');
            reply_body = read(obj.serial_port, reply_length, 'uint8');
            crc = read(obj.serial_port, 1, 'uint16');

            % OBS: The start sequence and both CRC are being returned in
            % integer format. They can be visualized as hex using 'dec2hex'
            error_checking = [start_sequence; header_CRC; crc];
        end

        function reply = COMM(obj, baud_rate, data_bits, parity, stop_bits, hardware_handshaking)
            reply = obj.sendCommandAndGetReply(sprintf('COMM %s%s%s%s%s', baud_rate, data_bits, parity, stop_bits, hardware_handshaking));
        end

        function reply = ECHO(obj, message)
            reply = obj.sendCommandAndGetReply(sprintf('ECHO %s', message));
        end

        function reply = GET(obj, user_parameter_name)
            reply = obj.sendCommandAndGetReply(sprintf('GET %s', user_parameter_name));
        end

        function reply = INIT(obj)
            reply = obj.sendCommandAndGetReply('INIT ');
        end

        function reply = LED(obj, port_handle, led_number, state)
            reply = obj.sendCommandAndGetReply(sprintf('LED %s%s%s', port_handle, led_number, state));
        end

        function reply = PDIS(obj, port_handle)
            reply = obj.sendCommandAndGetReply(sprintf('PDIS %s', port_handle));
        end

        function reply = PENA(obj, port_handle, tool_tracking_priority)
            reply = obj.sendCommandAndGetReply(sprintf('PENA %s%s', port_handle, tool_tracking_priority));
        end

        function reply = PHF(obj, port_handle)
            reply = obj.sendCommandAndGetReply(sprintf('PHF %s', port_handle));
        end

        function reply = PHINF(obj, port_handle, reply_option)
            reply = obj.sendCommandAndGetReply(sprintf('PHINF %s%s', port_handle, reply_option));
        end

        function reply = PHSR(obj, reply_option)
            reply = obj.sendCommandAndGetReply(sprintf('PHSR %s', reply_option));
        end

        function reply = PINIT(obj, port_handle)
            reply = obj.sendCommandAndGetReply(sprintf('PINIT %s', port_handle));
        end

        function reply = PPRD(obj, port_handle, srom_device_address)
            reply = obj.sendCommandAndGetReply(sprintf('PPRD %s%s', port_handle, srom_device_address));
        end

        function reply = PPWR(obj, port_handle, srom_device_address, srom_device_data)
            reply = obj.sendCommandAndGetReply(sprintf('PPWR %s%s%s', port_handle, srom_device_address, srom_device_data));
        end

        function reply = PSEL(obj, port_handle, tool_srom_device_id)
            reply = obj.sendCommandAndGetReply(sprintf('PSEL %s%s', port_handle, tool_srom_device_id));
        end

        function reply = PSOUT(obj, port_handle, gpio_1_state, gpio_2_state, gpio_3_state)
            reply = obj.sendCommandAndGetReply(sprintf('PSOUT %s%s%s%s', port_handle, gpio_1_state, gpio_2_state, gpio_3_state));
        end

        function reply = PSRCH(obj, port_handle)
            reply = obj.sendCommandAndGetReply(sprintf('PSRCH %s', port_handle));
        end

        function reply = PURD(obj, port_handle, user_srom_device_address)
            reply = obj.sendCommandAndGetReply(sprintf('PURD %s%s', port_handle, user_srom_device_address));
        end

        function reply = PUWR(obj, port_handle, user_srom_device_address, user_srom_device_data)
            reply = obj.sendCommandAndGetReply(sprintf('PUWR %s%s%s', port_handle, user_srom_device_address, user_srom_device_data));
        end

        function reply = PVWR(obj, port_handle, start_address, tool_definition_data)
            reply = obj.sendCommandAndGetReply(sprintf('PUWR %s%s%s', port_handle, start_address, tool_definition_data));
        end

        function reply = RESET(obj, reset_option)
            reply = obj.sendCommandAndGetReply(sprintf('RESET %s', reset_option));
        end

        function reply = SFLIST(obj, reply_option)
            reply = obj.sendCommandAndGetReply(sprintf('SFLIST %s', reply_option));
        end

        function reply = TSTART(obj, reply_option)
            reply = obj.sendCommandAndGetReply(sprintf('TSTART %s', reply_option));
        end

        function reply = TSTOP(obj)
            reply = obj.sendCommandAndGetReply('TSTOP ');
        end

        function reply = TTCFG(obj, port_handle)
            reply = obj.sendCommandAndGetReply(sprintf('TTCFG %s', port_handle));
        end

        function reply = TX(obj, reply_option)
            reply = obj.sendCommandAndGetReply(sprintf('TX %s', reply_option));
        end

        function reply = VER(obj, reply_option)
            reply = obj.sendCommandAndGetReply(sprintf('VER %s', reply_option));
        end

        function reply = VSEL(obj, volume_number)
            reply = obj.sendCommandAndGetReply(sprintf('VSEL %s', volume_number));
        end

    end

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %             DESTRUCTOR               %
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    methods

        function delete(obj)
            %
            % delete()
            %
            % "Maybe I should send some cleanup commands to the Aurora SCU
            % before closing the program." - Geraldes A.A.
            % Possible commands are:
            %   - PDIS for the Port Handles that have been enabled
            %   - PHF for the Port Handles that have been initialized
            %   - RESET
            clear obj.serial_port;
        end

    end

end
