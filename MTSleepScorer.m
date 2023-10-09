classdef MTSleepScorer < handle
    %   Copyright 2021 Michael J. Prerau, Ph.D. - http://www.sleepEEG.org
    %   This work is licensed under a Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International License.
    %   (http://creativecommons.org/licenses/by-nc-sa/4.0/)

    %%%%%%%%%%%%%%%% public properties %%%%%%%%%%%%%%%%%%
    properties (Access = public)
        %Replace handling with Event Marker
        event_marker;

        %Number of stages (3 or 5)
        numstages;

        %File info
        data_path; %Loading default
        save_path; %Saving Default
        file_name; %Current file
        save_fname; %Scoring save file

        %Scorer initials
        initials;

        %Main figure
        mainfig_h;
        %Main figure axes array
        axes_main;
    end

    %%%%%%%%%%%%%%%% private properties %%%%%%%%%%%%%%%%%%
    properties (Access = private)
        %Loaded data
        channel_labels;
        curr_channel;
        num_channels;
        Fs;

        %Spectrogram properties
        stimes;
        sfreqs;
        scube;
        spect_title_h;
        curr_resolution = 1;

        %Spectrogram parameters
        mt_params;
        mt_param_scales;

        %Message textboxes
        msg_textbox_h;
        zoom_textbox_h;
        title_textbox_h;

        %Popup handles
        popfig_h;
        popfigax_h;

        %Clim handles
        clim_sliders_h;
        clim_editboxes_h;
        autoscale_h;

        %Help window handles
        helpfig_h;

        %Hypnogram graphics objects
        zoomrect;
        hypnoline;

        %Spectrogram graphics object
        spect_h;
        %Channel title
        h_spect_title;

        %Slider objects
        zoom_slider;
        pan_slider;

    end

    %%%%%%%%%%%%%%% public methods %%%%%%%%%%%%%%%%%%%%%%
    methods (Access = public)

        %***********************************************
        %             CONSTRUCTOR METHOD
        %***********************************************

        function obj = MTSleepScorer(varargin)
            %Run the initialization script
            MT_scoring_init_script;

            %Set default paths
            obj.data_path = data_path;
            obj.save_path = save_path;

            %Set staging MT parameters
            obj.mt_params = mt_params;
            obj.mt_param_scales = mt_param_scales;

            %Load data
            obj.load_data;

            %Set up initial figure
            obj.init_fig;
        end
    end

    methods (Access = private)
        %************************************************************
        %                       LOAD DATA
        %************************************************************
        function load_data(obj)
            %---------------------------------------------------------
            %                 SELECT DATA AND LOAD
            %---------------------------------------------------------
            %Close all other figures
            c=get(0,'children');
            if ~isempty(c)
                for i=1:length(c)
                    delete(c(i));
                end
            end
            clc;

            %Get the initials of the scorer to be used for saving
            prompt={'Enter scorer initials:';};
            name='Enter Scorer Initials';
            numlines=1;
            defaultanswer={''};
            answer=inputdlg(prompt,name,numlines,defaultanswer);

            %Return if no answer
            if isempty(answer)
                return;
            end

            obj.initials=answer{1};

            if ~exist(obj.data_path,'dir')
                error('Invalid data path');
            end

            if ~exist(obj.save_path,'dir')
                error('Invalid save path');
            end


            %Let the user select the data file to load
            d=dir(fullfile(obj.data_path,'*.edf'));

            str = sort({d.name});
            s=listdlg('PromptString','Select a file:',...
                'SelectionMode','single',...
                'ListString',str);

            obj.file_name = str{s};

            %Load the file
            [~, shdr] = blockEdfLoad(fullfile(obj.data_path,obj.file_name));
            labels = {shdr.signal_labels};
            s=listdlg('PromptString','Select channels to load:',...
                'SelectionMode','multiple',...
                'ListString',labels);

            h=msgbox(['Loading ' obj.file_name '...']);

            %Load EDF
            [hdr, shdr, data] = blockEdfLoad(fullfile(obj.data_path,obj.file_name),labels(s));

            obj.Fs = hdr.samplingfrequency;
            obj.channel_labels = {shdr.signal_labels};
            obj.num_channels = length(obj.Fs);

            close(h);
            res_name = {'full night', 'stage', 'microevent'};

            %Make sure to start parallel pool if available
            if license('test','distrib_computing_toolbox')
                gcp;
            end

            %Loop over resolutions
            for res = 1:length(obj.mt_params)
                params = obj.mt_params{res};

                f = waitbar(0,['Computing ' res_name{res}  ' multitaper spectrograms...']);

                %Find channels that need to be rejected because of a different
                %duration
                skipped_chans = false(1, obj.num_channels);

                %Compute MTS for each channel
                for ii = 1:obj.num_channels
                    %Preallocate first time around
                    if ii == 1
                        [spect,obj.stimes{res},obj.sfreqs{res}] = multitaper_spectrogram_mex(data{ii}, obj.Fs(ii), [params.frequency_range(1) min(params.frequency_range(2), obj.Fs(ii)/2)], ...
                            params.taper_params, params.window_params,params.min_nfft, params.detrend_opt, params.weighting, false, false);

                        spect_size = size(spect);
                        obj.scube{res} = zeros([obj.num_channels, spect_size]);
                    else
                        spect = multitaper_spectrogram_mex(data{ii}, obj.Fs(ii), [params.frequency_range(1) min(params.frequency_range(2), obj.Fs(ii)/2)], ...
                            params.taper_params, params.window_params,params.min_nfft, params.detrend_opt, params.weighting, false, false);
                    end

                    %Check for channels of different duration
                    if ~any(size(spect) - spect_size)
                        obj.scube{res}(ii,:,:) = pow2db(spect);
                    else
                        skipped_chans(ii) = true;
                    end

                    waitbar(ii/obj.num_channels,f,['Computing ' res_name{res}  ' multitaper spectrograms...']);
                end
                close(f);

                %Remove skipped channels
                if any(skipped_chans)
                    h = msgbox(['Skipped channels with different duration: ' sprintf('"%s" ', obj.channel_labels{skipped_chans})]);
                    pause(2);

                    if ishandle(h)
                        close(h);
                    end

                    obj.scube{res} = obj.scube{res}(~skipped_chans,:,:);
                    obj.num_channels = sum(~skipped_chans);
                    obj.channel_labels = obj.channel_labels(~skipped_chans);
                end
            end

            obj.curr_channel = 1;

            %UPDATE TO FIX DIRECTORY
            obj.save_fname=fullfile(obj.save_path,['/scored_' obj.initials '_' obj.file_name(1:end-4) '.mat']);
            obj.numstages=3;
        end
        %---------------------------------------------------------
        %                  SET UP MAIN FIGURE
        %---------------------------------------------------------
        function init_fig(obj)
            %Set up the figure (hide until complete)
            obj.mainfig_h=figure('units','normalized','position',[0 0 .6 .6],'units','normalized',...
                'color','w','KeyPressFcn',@obj.handle_keys,'visible','off','windowbuttonupfcn',@obj.save_scoring);

            %Make axes
            obj.axes_main(1) = axes('Parent',obj.mainfig_h,'Position',[0.05 0.82 0.9 0.1]); %Hypnogram
            obj.axes_main(2) = axes('Parent',obj.mainfig_h,'Position',[0.05 0.1 0.9 0.64]); %Spectrogram

            %Create text boxes
            obj.msg_textbox_h=annotation(obj.mainfig_h,'textbox',...
                [0.7 0.006 0.7 0.02],...
                'String',{' '},...
                'FontSize',14,'HorizontalAlignment','right',...
                'FitBoxToText','off',...
                'LineStyle','none');

            obj.zoom_textbox_h=annotation(obj.mainfig_h,'textbox',...
                [0.02 0.87 0.19 0.1],...
                'String',{' '},...
                'FontSize',14,...
                'FitBoxToText','off',...
                'LineStyle','none');

            obj.title_textbox_h=annotation(obj.mainfig_h,'textbox',...
                [0.43 0.957 0.12 0.026],...
                'String',strrep(obj.file_name(1:end-4),'_','-'),...
                'FontWeight','bold',...
                'FontSize',24,...
                'FitBoxToText','off',...
                'LineStyle','none');


            % ---------------------------------------------------------
            %                        PLOT INITIAL DATA
            % ---------------------------------------------------------
            %Plot the hypnogram
            axes(obj.axes_main(1));
            if obj.numstages==3
                set(obj.axes_main(1),'ylim',[2.5 6.5],'ytick',3:6,'yticklabel',{'NREM','REM','Wake','Arousal'},'xtick',[]);
            else
                set(obj.axes_main(1),'ylim',[.5 5.5],'ytick',1:5,'yticklabel',{'N3','N2','N1','REM','Wake','Arousal'},'xtick',[]);
            end
            obj.h_spect_title=title('');
            xlim(obj.stimes{obj.curr_resolution}([1 end]));

            hold on

            %Create a blank hypnogram
            yl = ylim(obj.axes_main(1));
            obj.zoomrect=fill([0 obj.stimes{obj.curr_resolution}(end) obj.stimes{obj.curr_resolution}(end) 0],[yl(1) yl(1) yl(2) yl(2)],[.9 .9 1],'edgecolor','none');
            obj.hypnoline=plot(obj.stimes{obj.curr_resolution}([1 end]),[0 0],'color','k','linewidth',2);

            %Plot the initial spectrogram
            axes(obj.axes_main(2));
            obj.spect_h=imagesc(obj.stimes{obj.curr_resolution}, obj.sfreqs{obj.curr_resolution}, squeeze(obj.scube{obj.curr_resolution}(obj.curr_channel,:,:)));

            axis xy;
            climscale;
            topcolorbar(.1,.01,.03);
            colormap(jet(2^10));
            ylabel('Frequency (Hz)');
            obj.spect_title_h = title(['Sleep Spectrogram: ' obj.channel_labels(obj.curr_channel)],'FontWeight','bold','FontSize',18,'units','normalized');
            obj.spect_title_h.Position(2) = obj.spect_title_h.Position(2) + .05;

            %Plot xticks in HH:MM:SS every 30 min
            min_step = 30*60;
            set(obj.axes_main(2),'xtick',0:min_step:obj.stimes{obj.curr_resolution}(end),'xticklabel',datestr((0:min_step:obj.stimes{obj.curr_resolution}(end))*datefact,'HH:MM:SS'));

            %Link to main figure
            obj.mainfig_h.UserData=obj.mainfig_h;


            %---------------------------------------------------------
            %                       ADD EVENT MARKER
            %---------------------------------------------------------
            %
            %Call event marker class to mark on the image
            %obj = EventMarker(event_axis, xbounds, ybounds, event_types, event_list, line_colors, font_size, motioncallback)
            axes(obj.axes_main(2));
            em=EventMarker(obj.axes_main(2),xlim(obj.axes_main(2)), ylim(obj.axes_main(2)), [], [], [], 15, @obj.EM_callback);


            %obj.add_event_type(EventObject(<event type name>, <event ID>, <region? vs. point>, <bounded to yaxis?>)
            if obj.numstages == 3
                em.add_event_type(EventObject('W',5,false,false));
                em.add_event_type(EventObject('R',4,false,false));
                em.add_event_type(EventObject('N',3,false,false));
                em.add_event_type(EventObject('A',6,false,false));
                em.add_event_type(EventObject([],7,true,false));
            elseif obj.numstages == 5
                em.add_event_type(EventObject('W',5,false,false));
                em.add_event_type(EventObject('R',4,false,false));
                em.add_event_type(EventObject('N1',3,false,false));
                em.add_event_type(EventObject('N2',2,false,false));
                em.add_event_type(EventObject('N3',1,false,false));
                em.add_event_type(EventObject('A',6,false,false));
                em.add_event_type(EventObject([],7,true,false));
            else
                error('Must have either 3 or 5 stages');
            end

            %Add to main object
            obj.event_marker = em;

            %Load scoring if save file exists
            if exist(obj.save_fname,'file')
                obj.event_marker.load(obj.save_fname);
            else
                %Add a default event at time 0
                obj.event_marker.mark_event(5, 0);
            end

            %---------------------------------------------------------
            %                        CLIM SLIDERS
            %---------------------------------------------------------
            %Create the sliders
            cx = caxis(obj.axes_main(2));
            clim_bound=(cx(2)-cx(1))/2-.0001;
            minslider_h = uicontrol(obj.mainfig_h,'units','normalized','Style','slider',...
                'Max',cx(1)+clim_bound,'Min',cx(1)-clim_bound,'Value',cx(1),...
                'SliderStep',[0.05 0.2],...
                'Position',[0.8979    0.9653    0.0552    0.0217]);
            maxslider_h = uicontrol(obj.mainfig_h,'units','normalized','Style','slider',...
                'Max',cx(2)+clim_bound,'Min',cx(2)-clim_bound,'Value',cx(2),...
                'SliderStep',[0.05 0.2],...
                'Position',[0.8979    0.94    0.0552    0.0217]);

            obj.clim_sliders_h=[maxslider_h minslider_h];

            %Create the edit boxes for manual entry of parameter values
            minedit_h=uicontrol(obj.mainfig_h,'units','normalized','Style','edit','string',get(maxslider_h,'value'),'Position',[0.9542 0.9425 0.0352 0.0217],'backgroundcolor',get(obj.mainfig_h,'color'),'horizontalalign','right');
            maxedit_h=uicontrol(obj.mainfig_h,'units','normalized','Style','edit','string',get(minslider_h,'value'),'Position',[0.9542 0.9679 0.0352 0.0217],'backgroundcolor',get(obj.mainfig_h,'color'),'horizontalalign','right');

            obj.autoscale_h = uicontrol(obj.mainfig_h,'units','normalized','string','Autoscale','Position',[0.9542 0.9225 0.0352 0.0217],'backgroundcolor',...
                get(obj.mainfig_h,'color'),'horizontalalign','center','callback',@obj.clim_autoscale);

            %Array of all edit box handles
            obj.clim_editboxes_h=[maxedit_h minedit_h];

            %Set continuous callbaxs for the sliders
            addlistener(maxslider_h,'ContinuousValueChange',@obj.clim_slider_update);
            addlistener(minslider_h,'ContinuousValueChange',@obj.clim_slider_update);

            %Make Labels
            uicontrol(obj.mainfig_h,'units','normalized','Style','text','string','Clim Min','Position',[0.8637 0.9718 0.0352 0.0158],'backgroundcolor',get(obj.mainfig_h,'color'),'horizontalalign','right');
            uicontrol(obj.mainfig_h,'units','normalized','Style','text','string','Clim Max','Position', [0.8637 0.9479 0.0352 0.0158],'backgroundcolor',get(obj.mainfig_h,'color'),'horizontalalign','right');

            %Set the edit box callbacks
            set(maxedit_h,'callback',@obj.clim_edit_update);
            set(minedit_h,'callback',@obj.clim_edit_update);

            %---------------------------------------------------------
            %               SET UP THE ZOOM/PAN SLIDERS
            %---------------------------------------------------------
            [obj.zoom_slider, ~]=scrollzoompan(obj.axes_main(2),'x', @obj.update_zoom, @obj.update_pan);%, bounds);
            set(obj.zoom_slider,'min',10);

            %---------------------------------------------------------
            %                SLICE POPUP WINDOW
            %---------------------------------------------------------
            %Activate slice popups
            [obj.popfig_h, obj.popfigax_h]=slicepopup(obj.mainfig_h, obj.axes_main(2), obj.stimes{obj.curr_resolution}, obj.sfreqs{obj.curr_resolution}, [],  'Time (s)','Frequency (Hz)','Power (dB)', 'y', 0);

            %Adjust size and axes
            set(obj.popfig_h,'units','normalized','position',[ 0   0.7   1 .2],'color','w','CloseRequestFcn',@obj.toggle_visible,'WindowKeyPressFcn',{@obj.toggle_with_key,'u'});
            set(obj.popfigax_h,'xlim',[.5 20],'ylim',caxis(obj.axes_main(2)));

            obj.update_hypno([]);
            obj.update_timetext;
            set(obj.mainfig_h,'CloseRequestFcn',@obj.close_all);

            obj.mainfig_h.Visible = 'on';


            %---------------------------------------------------------
            %                        HELP WINDOW
            %---------------------------------------------------------
            obj.display_help;
        end

        %************************************************************
        %                    HELP FUNCTION
        %************************************************************
        function display_help(obj)
            obj.helpfig_h=figure('units','normalized','position',[0 .7 .1 .25],'color','w','name','EEG Viewer','menubar','none');
            axes('units','normalized','position',[0 0 1 .8]);
            text('position',[.05 .7],'string',...
                {'Keyboard Shortcuts:',...
                '',...
                '  left/right arrow (scroll wheel): Pan screen-width'...
                '  up/down arrow (shift + scroll wheel): Zoom'...
                '  z: Set zoom window size'...
                ''...
                '  u: Toggle slice power spectrum'...
                '  d: Create 3D popout of region'...
                '',...
                '  w/1: Add Wake stage'...
                '  r/2: Add REM stage'...
                '  n/3: Add NREM stage'...
                '  a: Add Arousal event'...
                '',...
                '  s: Add Spindle event'...
                '',...
                '  h: Toggle this help window'...
                '  q: Quit the program'...
                },'fontsize',12)
            axis off;

            set(obj.helpfig_h,'CloseRequestFcn',@obj.toggle_visible,'WindowKeyPressFcn',{@obj.toggle_with_key,'h'});

            obj.helpfig_h.UserData=obj.mainfig_h;

        end

        %************************************************************
        %                       UPDATE DURING ZOOM
        %************************************************************
        function update_zoom(obj)
            obj.update_timetext;
            obj.update_zoomrect;
            obj.update_resolution;
        end

        %************************************************************
        %                   UPDATE THE DURING PAN
        %************************************************************
        function update_pan(obj)
            obj.update_timetext;
            obj.update_zoomrect;
        end

        %************************************************************
        %     FUNCTION DURING EVENT MARKER MOVEMENT
        %************************************************************
        function EM_callback(obj, emarker_h, varargin)

            %Grab the current position of the sliding event marker
            if strcmpi(class(emarker_h),'images.roi.Line') || strcmpi(class(emarker_h),'images.roi.Rectangle')
                emarker_pos = emarker_h.Position;
            else
                emarker_pos = getPosition(emarker_h);
            end
            event_time = emarker_pos(1,1);

            %Update the hypnogram
            obj.update_hypno(event_time);
        end

        %************************************************************
        %     UPDATE THE TIME WINDOW TEXT WHEN THE LINES ARE MOVED
        %************************************************************
        function update_timetext(obj)
            xl = xlim(obj.axes_main(2));
            set(obj.zoom_textbox_h,'string',...
                sprintf(['Time Range:\t\t\t' datestr(xl(1)*datefact,'HH:MM:SS') ' - ' datestr(xl(2)*datefact,'HH:MM:SS')...
                '\nWindow Size:\t\t' datestr(diff(xl)*datefact,'HH:MM:SS')]));
        end

        %************************************************************
        %     UPDATE THE ZOOM RECTANGLE WHEN THE LINES ARE MOVED
        %************************************************************
        function update_zoomrect(obj)
            xl = xlim(obj.axes_main(2));
            set(obj.zoomrect,'xdata',[xl fliplr(xl)]);
        end

        %************************************************************
        %     UPDATE THE RESOLUTION OF THE SPECTROGRAM
        %************************************************************
        function update_resolution(obj)
            xl = xlim(obj.axes_main(2));
            dt = diff(xl);

            for ii = 1:length(obj.mt_param_scales)
                if obj.curr_resolution ~= ii && dt <= obj.mt_param_scales(ii) && dt>obj.mt_param_scales(ii+1)
                    obj.spect_h.CData=squeeze(obj.scube{ii}(obj.curr_channel,:,:));
                    obj.spect_h.XData = obj.stimes{ii};
                    obj.spect_h.YData = obj.sfreqs{ii};

                    obj.curr_resolution = ii;
                end
            end

            set(obj.zoomrect,'xdata',[xl fliplr(xl)]);
        end


        %************************************************************
        %     UPDATE THE HYPNOGRAM WHEN THE LINES ARE MOVED
        %************************************************************
        function update_hypno(obj, event_time)

            %Get all the stage events and times
            event_types = [obj.event_marker.event_list.type_ID];
            stage_inds = event_types<=6; %Pick only stages
            stage_vals = event_types(stage_inds);
            stage_times = cellfun(@(x)x.XData(1),{obj.event_marker.event_list(stage_inds).obj_handle});

            if ~isempty(event_time)
            %Get selected stage
            selected_ind = obj.event_marker.selected_ind;
            selected_stage = obj.event_marker.event_list(selected_ind).type_ID;

            %Return if not a stage time
            if selected_stage>6
                return;
            end

            %Find the original stage time
            selected_time_old = obj.event_marker.event_list(selected_ind).obj_handle.XData(1);

            %Find and update the time corresponding to the selected stage
            selected_ind_new = stage_times == selected_time_old;

            if any(selected_ind_new)
                stage_times(selected_ind_new) = event_time;
            end
            end

            %Sort the times and plot the hypnogram
            [stage_times,sind]=sort(stage_times);
            stage_vals=stage_vals(sind);

            %Stairs is SLOW
            x=[obj.stimes{obj.curr_resolution}(1) stage_times obj.stimes{obj.curr_resolution}(end)];
            y=[0 stage_vals(:)' 0];
            X=reshape(repmat(x,2,1),1,length(x)*2);
            Y=reshape(repmat(y,2,1),1,length(y)*2);
            set(obj.hypnoline,'ydata',Y(1:end-1),'xdata',X(2:end));
            drawnow;
        end

        %************************************************************
        %                   UPDATE SPECTROGRAM CHANNEL
        %************************************************************
        function update_channel(obj, new_chan)

            if new_chan<1 || new_chan>obj.num_channels
                return;
            end

            obj.curr_channel = new_chan;

            obj.spect_h.CData=squeeze(obj.scube{obj.curr_resolution}(new_chan,:,:));
            obj.spect_title_h.String = ['Sleep Spectrogram: ' obj.channel_labels(obj.curr_channel)];
        end

        %************************************************************
        %                   TOGGLE POPUP VISIBILITY
        %************************************************************
        function toggle_visible(~, src, varargin)
            %Toggles the current visibility of the popup
            if strcmp(get(src,'visible'),'on')
                set(src,'visible','off');
            else
                set(src,'visible','on');
            end

            %Resets focus to the main window
            set(0,'currentfigure',get(get(gcbo,'parent'),'parent'));
        end

        %************************************************************
        %    HELPER FUNCTION TO CLOSE WINDOWS WITH A HOTKEY
        %************************************************************
        function toggle_with_key(obj, src,event,keychar)
            if lower(event.Key) == keychar
                toggle_visible(obj, src,event);
            end
        end

        %************************************************************
        %               TOGGLE SPECTRUM RESOLUTION
        %************************************************************
        function toggle_spectrum(varargin)
            if strcmpi(get(obj.spect_h,'visible'),'off')
                set(obj.spect_h,'visible','on');
                set(GUI_data.h_stagespect,'visible','off');
            else
                set(obj.spect_h,'visible','off');
                set(obj.h_stagespect,'visible','on');
            end
        end

        %************************************************************
        %              SAVE USER SCORING DATA
        %************************************************************
        function save_scoring(obj, varargin)
            obj.msg_textbox_h.String = 'Saving...';
            obj.event_marker.save(obj.save_fname);
            obj.msg_textbox_h.String = '';
        end

        %************************************************************
        %              UPDATE CLIM SLIDER
        %************************************************************
        function clim_slider_update(obj, varargin)
            maxval=get(obj.clim_sliders_h(1),'value');
            minval=get(obj.clim_sliders_h(2),'value');

            if maxval<=get(obj.clim_sliders_h(2),'value')
                maxval=get(obj.clim_sliders_h(2),'value')+1e-10;
            end

            if minval>=get(obj.clim_sliders_h(1),'value')
                minval=get(obj.clim_sliders_h(1),'value')-1e-10;
            end

            cx=[minval maxval];

            % disp(clims);
            set(obj.axes_main(2),'clim',cx);
            set(obj.clim_editboxes_h(1),'string',num2str(cx(1)));
            set(obj.clim_editboxes_h(2),'string',num2str(cx(2)));
        end

        %************************************************************
        %              UPDATE CLIM EDIT BOX
        %************************************************************
        function clim_edit_update(obj, varargin)
            %Get the new value from the edited text box
            minval=str2double(get(obj.clim_editboxes_h(1),'string'));
            maxval=str2double(get(obj.clim_editboxes_h(2),'string'));

            if maxval<=get(obj.clim_sliders_h(2),'value')
                maxval=get(obj.clim_sliders_h(2),'value')+.001;
            end

            if minval>=get(obj.clim_sliders_h(1),'value')
                minval=get(obj.clim_sliders_h(1),'value')-.001;
            end

            cx=[minval maxval];

            if maxval>get(obj.clim_sliders_h(1),'max')
                set(obj.clim_sliders_h(1),'max',maxval,'value',maxval);
            elseif maxval<get(obj.clim_sliders_h(1),'min')
                set(obj.clim_sliders_h(1),'min',maxval,'value',maxval);
            end

            if minval>get(obj.clim_sliders_h(2),'max')
                set(obj.clim_sliders_h(2),'max',minval,'value',minval);
            elseif minval<get(obj.clim_sliders_h(2),'min')
                set(obj.clim_sliders_h(2),'min',minval,'value',minval);
            end

            set(obj.clim_sliders_h(1),'value',maxval);
            set(obj.clim_sliders_h(2),'value',minval);
            set(obj.clim_editboxes_h(1),'string',minval);
            set(obj.clim_editboxes_h(2),'string',maxval);
            set(obj.axes_main(2),'clim',cx);
        end


        %************************************************************
        %              UPDATE AUTOSCALE
        %************************************************************
        function clim_autoscale(obj, varargin)

            %Autoscale colormap
            climscale(obj.axes_main(2),[],true);
            cx = caxis(obj.axes_main(2));

            set(obj.clim_sliders_h(1),'value', cx(2));
            set(obj.clim_sliders_h(2),'value', cx(1));

            set(obj.clim_editboxes_h(1),'string',num2str(cx(1)));
            set(obj.clim_editboxes_h(2),'string',num2str(cx(2)));
        end

        %************************************************************
        %              AUTOSCORE TF_SIGMA PEAKS
        %************************************************************
        function autoscore_TFsigma_peaks(obj, varargin)

            [hdr, ~, data] = blockEdfLoad(fullfile(obj.data_path,obj.file_name),{obj.channel_labels{obj.curr_channel}});

            estage = [obj.event_marker.event_list.type_ID];
            stage_inds = estage<=6; %Pick only stages
            estage = estage(stage_inds);

            etimes = cellfun(@(x)x.XData(1),{obj.event_marker.event_list(stage_inds).obj_handle});

            %Sort the times and plot the hypnogram
            [stage_times,sind]=sort(etimes);
            stage_vals=estage(sind);

            h = msgbox('Autodetecting TF_sigma Peaks...');
            [ spindle_table, ~, ~, ~, ~ ] = ...
                TF_peak_detection(data{1},  hdr.samplingfrequency, [stage_times(:), stage_vals(:)],...
                'to_plot',false, 'spindle_freq_range',[10,16], 'detection_stages',3);
            delete(h);

            pos = [ spindle_table.Start_Time, spindle_table.Freq_Low,...
                spindle_table.Duration, spindle_table.Freq_High-spindle_table.Freq_Low ];
            obj.event_marker.mark_event(7,pos);

            obj.save_scoring;
        end


        %************************************************************
        %              UPDATE AUTOSCALE
        %************************************************************
        function pop_3d(obj, varargin)
            %Check for image processing toolbox
            v=ver;
            [installedToolboxes{1:length(v)}] = deal(v.Name);
            result = all(ismember('Image Processing Toolbox',installedToolboxes));

            if ~license('test','image_toolbox')
                msgbox('This function is only available with the Image Processing Toolbox');
                return
            end

            %Use drawrectangle if available
            if which('drawrectangle.m')
                h1 = drawrectangle('Label','Select Region and Hit Enter','Color',[1 0 0]);
            else
                h1 = imrect;
            end

            wait(h1);

            pos = h1.Position;

            delete(h1);

            finds = obj.sfreqs{obj.curr_resolution} >= pos(2) & obj.sfreqs{obj.curr_resolution} <= pos(2)+pos(4);
            tinds = obj.stimes{obj.curr_resolution} >= pos(1) & obj.stimes{obj.curr_resolution} <= pos(1)+pos(3);

            pop_spect = squeeze(obj.scube{obj.curr_resolution}(obj.curr_channel,finds,tinds));
            pop_sfreqs = obj.sfreqs{obj.curr_resolution}(finds);
            pop_stimes = obj.stimes{obj.curr_resolution}(tinds);

            figure
            surface(pop_stimes,pop_sfreqs,pop_spect,'edgecolor','none');
            xlabel('Times (s)');
            ylabel('Frequency (Hz)');
            zlabel('Power (dB)');
            colormap(jet)
            view(3);
            caxis(caxis(obj.axes_main(2)))
            camlight left
            camlight right
            material dull
            lighting phong
            shading interp

        end

        %************************************************************
        %                      HANDLE HOTKEYS
        %************************************************************
        function handle_keys(obj, ~, event)
            switch event.Key
                case {'backspace','delete'}
                    obj.event_marker.delete_selected;

            end

            %Check for hotkeys pressed
            switch lower(event.Character)
                case {'w', '1'}
                    obj.event_marker.mark_event(5);
                    obj.save_scoring;
                case {'r', '2'}
                    obj.event_marker.mark_event(4);
                    obj.save_scoring;
                case {'n', '3'}
                    obj.event_marker.mark_event(3);
                    obj.save_scoring;
                case 's'
                    obj.event_marker.mark_event(7);
                    obj.save_scoring;
                case 'a'
                    %Add artifact event
                    new_event = obj.event_marker.mark_event(6);
                    % 
                    % %Find the previous stage
                    % newID = new_event.event_ID;
                    % % [etimes, etypes, eIDs, isregion] = obj.event_marker.get_events;
                    % % 
                    % % %Remove all region events
                    % % eIDs = eIDs(~isregion);
                    % % etimes = etimes(~isregion);
                    % % etypes = etypes(~isregion);
                    % % 
                    % % eind = find(eIDs == newID);
                    % % etime = etimes(eind);
                    % % last_stage = etypes(max(eind-1,1));
                    % 
                    % %Mark previous stage 30s after
                    % obj.event_marker.mark_event(last_stage,etime+30);
                    obj.save_scoring;
                case 'h'
                    obj.toggle_visible(obj.helpfig_h);
                case 'u'
                    obj.toggle_visible(obj.popfig_h);
                case 'q'
                    obj.close_all;
                case 'd'
                    obj.pop_3d;
                case ','
                    new_chan = obj.curr_channel + 1;
                    if new_chan > obj.num_channels
                        new_chan = 1;
                    end
                    obj.update_channel(new_chan);
                case '.'
                    new_chan = obj.curr_channel - 1;
                    if new_chan < 1
                        new_chan = obj.num_channels;
                    end
                    obj.update_channel(new_chan);
                case '*'
                    obj.autoscore_TFsigma_peaks;
            end

            obj.update_hypno([]);
        end

       

        %************************************************************
        %               CLOSE ALL FIGURES CLEANLY
        %************************************************************
        function close_all(obj, varargin)

            choice=questdlg('Do you want to quit?','Quit Program');
            if strcmp(choice,'Yes')
                obj.save_scoring;
                h=msgbox('Scoring saved');
                pause(1);

                if ishandle(h)
                    close(h);
                end

                delete(obj.mainfig_h);
                delete(obj.popfig_h);
                delete(obj.helpfig_h);
            end
        end
    end
end
