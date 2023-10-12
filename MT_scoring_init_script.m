root = '/Users/Mike/code/projects/MTSleepScoring';

data_path =  fullfile(root,'/data');
save_path = fullfile(root,'/scoring');

%FULL NIGHT PARAMETERS
mt_full.frequency_range=[0.5 35]; %Limit frequencies from 0 to 35 Hz
mt_full.taper_params=[15 29]; %Time bandwidth and number of tapers
mt_full.window_params=[30 15]; %Window size is 30s with step size of 15s
mt_full.min_nfft=[]; %No minimum nfft
mt_full.detrend_opt='linear'; %linear detrend
mt_full.weighting='unity'; %weight each taper equally

%STAGE-LEVEL PARAMETERS
mt_stage.frequency_range=[0.5 35]; %Limit frequencies from 0 to 35 Hz
mt_stage.taper_params=[3 5]; %Time bandwidth and number of tapers
mt_stage.window_params=[6 1]; %Window size is 6s with step size of 1s
mt_stage.min_nfft=[]; %No minimum nfft
mt_stage.detrend_opt='linear'; %linear detrend
mt_stage.weighting='unity'; %weight each taper equally

%MICRO-EVENT PARAMETERS
mt_micro.frequency_range=[0.5 35]; %Limit frequencies from 0 to 35 Hz
mt_micro.taper_params=[2 3]; %Time bandwidth and number of tapers
mt_micro.window_params=[1 0.1]; %Window size is 1s with step size of 0.1s
mt_micro.min_nfft=2^10; %No minimum nfft
mt_micro.detrend_opt='constant'; %Make windows zero-mean
mt_micro.weighting='unity'; %weight each taper equally

%Load into cell array. 
mt_params{1} = mt_full;
mt_params{2} = mt_stage;
mt_params{3} = mt_micro;

%Set the scales for each of the params
mt_param_scales = [inf 1.5*3600 5*60 -inf];