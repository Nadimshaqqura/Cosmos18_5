classdef Cosmos15_8 < matlab.apps.AppBase
    properties (Access = public)  
        UIFigure, GridLayout, LeftPanel, RightPanel, uiaxes_obj
        ConnectButton, DisconnectButton, PreviewButton
        StartTrackingButton, StopTrackingButton
        SnapshotsEditField, ParticleSizeMicronEditField, ParticleSizePxEditField, SaveIntervalEditField
        ManualPanel, StepSizeEditField, StatusLabel
    end
    properties (Access = public)
        vid, idPtr, isTracking = false, LibraryLoaded = false
        AnalysisFigure, LogFileID
        % define the tracking region of intrest in the image  
        FixedROI = [400, 300, 1000, 600]  %% [minx miny width height]
        last_com_x = 0, last_com_y = 0 % com= center of mass
    end

    methods (Access = public)
        function togglePreview(obj)  %% connect camera
            if isempty(obj.vid) || ~isvalid(obj.vid)
                imaq_objs = imaqfind("DeviceID", 2);
                if ~isempty(imaq_objs), delete(imaq_objs); end
                obj.vid = videoinput("winvideo", 2, "BYRG_1928x1208"); % bei der Verwendung anderer kamera muss möglicherweise eingestellt werden
                set(obj.vid, 'ReturnedColorSpace', 'rgb'); 
            end
            cla(obj.uiaxes_obj);
            set(obj.uiaxes_obj, 'DataAspectRatio', [1 1 1], 'YDir', 'reverse', 'XLim', [0 1928], 'YLim', [0 1208]);
            if obj.PreviewButton.Value
                hImg = image(zeros(1208, 1928, 3, 'uint8'), 'Parent', obj.uiaxes_obj);
                preview(obj.vid, hImg);
            else
                stoppreview(obj.vid);
            end
        end

        function stopTracking(obj)
            obj.isTracking = false;
        end
    end

    methods (Access = private)
        function StartTrackingButtonPushed(obj, ~)
            if isempty(obj.vid), return; end
            try
                obj.isTracking = true;
                obj.StartTrackingButton.Enable = 'off';
                obj.StopTrackingButton.Enable = 'on';
                
                snaps = obj.SnapshotsEditField.Value; %number of snapshots ( dauer der messung)
                m_scale = obj.ParticleSizeMicronEditField.Value; %particle size micrometer
                p_scale = obj.ParticleSizePxEditField.Value; % particle size pixel
                save_int = obj.SaveIntervalEditField.Value; % saving and tracking intervall
                % file for the saved images
                timestampStr = datestr(now, 'yyyy-mm-dd_HH-MM-SS');
                folderName = "Tracking_" + timestampStr; mkdir(folderName);
                obj.LogFileID = fopen(fullfile(folderName, 'drift_values.csv'), 'w');
                fprintf(obj.LogFileID, 'Frame,sum_xdrift,sum_ydrift,t_drift,Mode\n');
                % take a snapshot, detect the particles, and define
                % tracking "borders" a, b and c. those are needed to avoid
                % problems when the particles at the edge of the image disappear from Region of intrest. 
                Bild1_Full = getsnapshot(obj.vid);
                Bild_Init = imcrop(Bild1_Full, obj.FixedROI);
                bw1 = bwareaopen(imcomplement(im2bw(rgb2gray(Bild_Init), graythresh(Bild_Init))), 5); %% objekte kleiner als 5px entfernt
                st1 = regionprops('table', bw1, 'Centroid');
                N_ges = size(st1, 1);
                a = round(0.25*N_ges); b = round(0.75*N_ges); c = max(1, b-a+1);
                
                xlist = zeros(c, snaps); ylist = zeros(c, snaps);
                xdrift_all = zeros(c * snaps, 1); ydrift_all = zeros(c * snaps, 1);
                rel_drift_log = zeros(snaps, 2); 
                com_history = zeros(snaps, 2);
                
                imgCount = 1; drift_ptr = 1; elapsedtime3 = 0.001; currentState = ""; 

                obj.AnalysisFigure = figure('Name', 'Monitor', 'NumberTitle', 'off');
                ax_ext = axes(obj.AnalysisFigure);
                hExtImg = image(ax_ext, zeros(1208, 1928, 3, 'uint8')); 
                hold(ax_ext, 'on');
                hCOM = plot(ax_ext, 0, 0, 'gx', 'MarkerSize', 15, 'LineWidth', 2);
                % main tracking loop
                %contains 2 tracking mechanisms:
                %1) detected particles > b --> tracking the drift of each
                %individual particle
                %2) detected particles < b due to aggregation--> considers
                %the whole system to track the center of mass weighted by
                %particle size
                for j = 1:snaps
                    if ~obj.isTracking || ~isvalid(obj.AnalysisFigure), break; end
                    loopTic = tic;
                    %take snapshot and detect particles
                    BildFull = getsnapshot(obj.vid);
                    set(hExtImg, 'CData', BildFull);
                    
                    BildCrop = imcrop(BildFull, obj.FixedROI);
                    bw = bwareaopen(imcomplement(im2bw(rgb2gray(BildCrop), graythresh(BildCrop))), 5);
                    st = regionprops('table', bw, 'Centroid', 'MajorAxisLength', 'MinorAxisLength');
                    
                    if size(st, 1) >= b %1) start individual tracking
                        newStatus = sprintf("Status: Precision Tracking (%d particles)", c);
                        xpos = st.Centroid(:,1); ypos = st.Centroid(:,2); % positions of the particles
                        xlist(:, j) = xpos(a:b); ylist(:, j) = ypos(a:b); % lists with the positions
                        obj.last_com_x = mean(xlist(:, j));
                        obj.last_com_y = mean(ylist(:, j));
                        
                        if j > 1
                            for i = 1:c 
                                %calculate drift of the particles based on distance to the nearest neighbour in the
                                %next fram
                                vx = xlist(i,j) - xlist(:,j-1); vy = ylist(i,j) - ylist(:,j-1);
                                rij = sqrt(vx.^2 + vy.^2); [~, min_i] = min(rij(rij > 0));
                                xdrift_all(drift_ptr) = xlist(i,j) - xlist(min_i,j-1); %drift in x 
                                ydrift_all(drift_ptr) = ylist(i,j) - ylist(min_i,j-1); %drift in y
                                drift_ptr = drift_ptr + 1;
                            end
                            %extract drift data
                            z1 = xdrift_all(drift_ptr-c : drift_ptr-1); z2 = ydrift_all(drift_ptr-c : drift_ptr-1); 
                            xout = ~isoutlier(z1); yout = ~isoutlier(z2); %remove outliers from drift values
                            %drift individual tracking ( first mechanism)
                            rel_drift_log(j, 1) = (mean(z1(xout)) * m_scale) / p_scale; %final drift values to be fed to the microcontroller
                            rel_drift_log(j, 2) = (mean(z2(yout)) * m_scale) / p_scale;
                        end
                    else
                        % second mechanism, track center of mass weighted
                        % by object sizes
                        newStatus = "Status: center of mass ";
                        weights = st.MajorAxisLength .* st.MinorAxisLength;
                        if ~isempty(weights)
                            obj.last_com_x = sum(st.Centroid(:,1) .* weights) / sum(weights); %last center of mass
                            obj.last_com_y = sum(st.Centroid(:,2) .* weights) / sum(weights);
                        elseif j > 1
                            obj.last_com_x = com_history(j-1,1); obj.last_com_y = com_history(j-1,2);
                        end
                        if j > 1 %% drift of center of mass (second mechanism)
                            
                            rel_drift_log(j, 1) = ((obj.last_com_x - com_history(j-1,1)) * m_scale) / p_scale;
                            rel_drift_log(j, 2) = ((obj.last_com_y - com_history(j-1,2)) * m_scale) / p_scale;
                        end
                        xlist(:, j) = obj.last_com_x; ylist(:, j) = obj.last_com_y;
                    end

                    com_history(j, :) = [obj.last_com_x, obj.last_com_y];
                    if ~strcmp(currentState, newStatus), obj.StatusLabel.Text = newStatus; currentState = newStatus; end
                    set(hCOM, 'XData', obj.last_com_x + obj.FixedROI(1), 'YData', obj.last_com_y + obj.FixedROI(2));
                    %if saving interval is reached, sum of the drifts of
                    %for the images until the saveing intervall is
                    %calculated
                  
                    if mod(j, save_int) == 0 && j > save_int
                        idx = (j-save_int+1):j; 
                        sum_xd = sum(rel_drift_log(idx, 1)); sum_yd = sum(rel_drift_log(idx, 2));
                        
                        if size(st, 1) >= b  % individual tracking
                            
                            mean_dist = sqrt(mean(rel_drift_log(idx,1))^2 + mean(rel_drift_log(idx,2))^2);
                            t_accel = sqrt((2 * mean_dist * 10^-6) / 0.001); %time for the movement of the stage
                            inst_dist = sqrt(rel_drift_log(j,1)^2 + rel_drift_log(j,2)^2);
                            elapsedtime2 = toc(loopTic); %timer
                            t_drift = (t_accel * inst_dist) / elapsedtime2; %drift during the exectution of the code and image processing
                            mov_drift = (elapsedtime3 * inst_dist) / elapsedtime2; % drift during the movement of the stage
                            %final drift value containt the sum of drifts+ compensation for stage movement+ compensation for drift during image processing                      
                            move_x = sum_xd + mov_drift + t_drift; 
                            move_y = sum_yd + mov_drift + t_drift;
                        else % center of mass
                            move_x = sum_xd; move_y = sum_yd; t_drift = 0;
                        end
                        % send order to the microcontroler to move
                        fprintf(obj.LogFileID, '%d,%.6f,%.6f,%.6f,%s\n', j, sum_xd, sum_yd, t_drift, currentState);
                        if obj.LibraryLoaded
                            calllib('Tango_DLL','LSX_MoveRel',obj.idPtr.Value, move_x, move_y, 0, 0, true);
                        end
                        imwrite(BildFull, fullfile(folderName, sprintf('%d.png', imgCount)));
                        imgCount = imgCount + 1;
                    end
                    drawnow limitrate;
                    moveTic = tic; elapsedtime3 = toc(moveTic); %timer for each loop run 
                end
            catch ME
                obj.StatusLabel.Text = "Error: " + ME.message;
            end
            if ~isempty(obj.LogFileID), fclose(obj.LogFileID); end
            obj.isTracking = false;
            obj.StartTrackingButton.Enable = 'on'; obj.StopTrackingButton.Enable = 'off';
        end

        function ConnectButtonPushed(obj, ~)  %%connect and define stage parameters
            try
                if ~libisloaded('Tango_DLL'), loadlibrary('Tango_DLL'); end
                obj.idPtr = libpointer('int32Ptr', 0);
                calllib('Tango_DLL', 'LSX_CreateLSID', obj.idPtr);
                if calllib('Tango_DLL', 'LSX_ConnectSimple', obj.idPtr.Value, -1, 'COM4', 57600, 0) == 0
                    %stage parameters
                    calllib('Tango_DLL', 'LSX_SetDimensions', obj.idPtr.Value, 1, 1, 1, 1); %dimension 1=micrometer
                    calllib('Tango_DLL', 'LSX_SetAccel', obj.idPtr.Value, 0.005, 0.005, 0.005, 0.005); %acceleration m/s^2
                    calllib('Tango_DLL', 'LSX_SetAccelFunc', obj.idPtr.Value, 1, 1, 1, 1); 
                    calllib('Tango_DLL', 'LSX_SetVel', obj.idPtr.Value, 5.0, 5.0, 5.0, 5.0); %velocity m/s
                    
                    obj.LibraryLoaded = true;
                    obj.StatusLabel.Text = "Status: Connected & Configured";
                    obj.StartTrackingButton.Enable = 'on'; obj.ManualPanel.Enable = 'on';
                    obj.ConnectButton.Enable = 'off'; obj.DisconnectButton.Enable = 'on';
                end
            catch ME, obj.StatusLabel.Text = "Error: " + ME.message; end
        end

        function MoveStage(obj, axis, dir) %% for stage movement buttons
            if ~obj.LibraryLoaded, return; end
          %$ calllib('Tango_DLL', 'LSX_WaitNext', obj.idPtr.Value);
            step = obj.StepSizeEditField.Value * dir;
            dx=0; dy=0; dz=0;
            if axis=='x', dx=step; elseif axis=='y', dy=step; else, dz=step; end
            calllib('Tango_DLL', 'LSX_MoveRel', obj.idPtr.Value, dx, dy, dz, 0, true);
        end

        function DisconnectAndClose(obj) %% disconnect the stage
            obj.isTracking = false;
            if ~isempty(obj.vid) && isvalid(obj.vid), stoppreview(obj.vid); delete(obj.vid); end
            if obj.LibraryLoaded, calllib('Tango_DLL', 'LSX_Disconnect', obj.idPtr.Value); end
            imaqreset; delete(obj.UIFigure);
        end

        function createComponents(obj) %buttons
            obj.UIFigure = uifigure('Position', [100 100 1000 650], 'Name', 'Cosmos 15.8 Hybrid', 'CloseRequestFcn', @(~,~) obj.DisconnectAndClose());
            obj.GridLayout = uigridlayout(obj.UIFigure, [1, 2], 'ColumnWidth', {260, '1x'});
            obj.LeftPanel = uipanel(obj.GridLayout, 'Title', 'Controls');
            obj.ConnectButton = uibutton(obj.LeftPanel, 'Position', [10 580 110 30], 'Text', 'Connect', 'ButtonPushedFcn', @(~,~) obj.ConnectButtonPushed);
            obj.DisconnectButton = uibutton(obj.LeftPanel, 'Position', [130 580 110 30], 'Text', 'Disconnect', 'Enable', 'off', 'ButtonPushedFcn', @(~,~) obj.DisconnectAndClose());
            obj.PreviewButton = uibutton(obj.LeftPanel, 'state', 'Position', [10 545 230 30], 'Text', 'Live Preview', 'ValueChangedFcn', @(~,~) obj.togglePreview());
            uilabel(obj.LeftPanel, 'Position', [10 510 100 22], 'Text', 'Snapshots:');
            obj.SnapshotsEditField = uieditfield(obj.LeftPanel, 'numeric', 'Position', [130 510 100 22], 'Value', 10000);
            uilabel(obj.LeftPanel, 'Position', [10 475 100 22], 'Text', 'Size (um):');
            obj.ParticleSizeMicronEditField = uieditfield(obj.LeftPanel, 'numeric', 'Position', [130 475 100 22], 'Value', 10.41);
            uilabel(obj.LeftPanel, 'Position', [10 440 100 22], 'Text', 'Size (px):');
            obj.ParticleSizePxEditField = uieditfield(obj.LeftPanel, 'numeric', 'Position', [130 440 100 22], 'Value', 9.5);
            uilabel(obj.LeftPanel, 'Position', [10 405 100 22], 'Text', 'Save Int:');
            obj.SaveIntervalEditField = uieditfield(obj.LeftPanel, 'numeric', 'Position', [130 405 100 22], 'Value', 20);
            obj.StartTrackingButton = uibutton(obj.LeftPanel, 'Position', [10 350 110 40], 'Text', 'START', 'Enable', 'off', 'ButtonPushedFcn', @(~,~) obj.StartTrackingButtonPushed);
            obj.StopTrackingButton = uibutton(obj.LeftPanel, 'Position', [130 350 110 40], 'Text', 'STOP', 'Enable', 'off', 'ButtonPushedFcn', @(~,~) obj.stopTracking());
            obj.ManualPanel = uipanel(obj.LeftPanel, 'Title', 'Manual Stage', 'Position', [10 15 240 250]);
            obj.StepSizeEditField = uieditfield(obj.ManualPanel, 'numeric', 'Position', [100 200 80 22], 'Value', 10);
            uibutton(obj.ManualPanel, 'Position', [85 150 60 30], 'Text', 'Y+', 'ButtonPushedFcn', @(~,~) obj.MoveStage('y', 1));
            uibutton(obj.ManualPanel, 'Position', [85 90 60 30], 'Text', 'Y-', 'ButtonPushedFcn', @(~,~) obj.MoveStage('y', -1));
            uibutton(obj.ManualPanel, 'Position', [20 120 60 30], 'Text', 'X-', 'ButtonPushedFcn', @(~,~) obj.MoveStage('x', -1));
            uibutton(obj.ManualPanel, 'Position', [150 120 60 30], 'Text', 'X+', 'ButtonPushedFcn', @(~,~) obj.MoveStage('x', 1));
            uibutton(obj.ManualPanel, 'Position', [20 40 90 30], 'Text', 'Z+', 'ButtonPushedFcn', @(~,~) obj.MoveStage('z', 1));
            uibutton(obj.ManualPanel, 'Position', [130 40 90 30], 'Text', 'Z-', 'ButtonPushedFcn', @(~,~) obj.MoveStage('z', -1));
            obj.RightPanel = uipanel(obj.GridLayout, 'Title', 'Monitor');
            obj.uiaxes_obj = uiaxes(obj.RightPanel, 'Position', [10 40 700 550]);
            obj.StatusLabel = uilabel(obj.RightPanel, 'Position', [10 10 400 22], 'Text', 'Status: Ready');
        end
    end
    
    methods (Access = public)
        function obj = Cosmos15_8
            createComponents(obj); registerApp(obj, obj.UIFigure);
        end
    end
end