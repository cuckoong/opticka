% 2 FIGURE GROUND state configuration file, this gets loaded by opticka via runExperiment class
% io = datapixx (digital I/O to plexon)
% s = screenManager
% sM = State Machine
% eL = eyelink manager
% lJ = LabJack (reward trigger to Crist reward system)
% bR = behavioural record plot
% obj.stimuli = our list of stimuli
% tS = general simple struct to hold variables for this run
%
%------------General Settings-----------------
tS.rewardTime = 160; %TTL time in milliseconds
tS.useTask = true;
tS.checkKeysDuringStimulus = false;
tS.recordEyePosition = true;
tS.askForComments = true;
tS.saveData = true; %*** save behavioural and eye movement data? ***
obj.useDataPixx = true; %*** drive plexon to collect data? ***
tS.dummyEyelink = false; 
tS.name = 'two-figure-ground';

luminancePedestal = [0.5 0.5 0.5];
fixX = 0;
fixY = 0;
firstFixInit = 0.7;
firstFixTime = [0.5];
firstFixRadius = 1;
obj.lastXPosition = fixX;
obj.lastYPosition = fixY;
strict = true;

targetFixInit = 0.75;
targetFixTime = [0.4];
targetRadius = 2;

eL.isDummy = tS.dummyEyelink; %use dummy or real eyelink?
eL.name = tS.name;
if tS.saveData == true; eL.recordData = true; end% save EDF file?
eL.sampleRate = 250;
eL.remoteCalibration = true; % manual calibration?
eL.calibrationStyle = 'HV5'; % calibration style
eL.modify.calibrationtargetcolour = [1 1 0];
eL.modify.calibrationtargetsize = 0.5;
eL.modify.calibrationtargetwidth = 0.01;
eL.modify.waitformodereadytime = 500;
eL.modify.devicenumber = -1; % -1 = use any keyboard

% X, Y, FixInitTime, FixTime, Radius, StrictFix
eL.updateFixationValues(fixX, fixY, firstFixInit, firstFixTime, firstFixRadius, strict);

%randomise stimulus variables every trial?
obj.stimuli.choice = [];
obj.stimuli.stimulusTable = [];

% allows using arrow keys to control this table during the main loop
% ideal for mapping receptive fields so we can twiddle parameters
obj.stimuli.controlTable = [];
obj.stimuli.tableChoice = 1;

% this allows us to enable subsets from our stimulus list
% numbers are the stimuli in the opticka UI
obj.stimuli.stimulusSets = {[1 2 3 4 5 6]};
obj.stimuli.setChoice = 1;
showSet(obj.stimuli);

%which stimulus in the list is used for a fixation target?
obj.stimuli.fixationChoice = [3 5];

%----------------------State Machine States-------------------------
% these are our functions that will execute as the stateMachine runs,
% in the scope of the runExperiemnt object.

%pause entry
pauseEntryFcn = { @()rstop(io); ...
	@()setOffline(eL); ... %set eyelink offline
	@()stopRecording(eL); ...
	@()edfMessage(eL,'TRIAL_RESULT -10'); ...
	@()disableFlip(obj); ...
	};

%pause exit
pauseExitFcn = { @()rstart(io) };%lets unpause the plexon!

prefixEntryFcn = { @()enableFlip(obj); };
prefixFcn = { @()draw(obj.stimuli) };

%fixate entry
fixEntryFcn = { @()statusMessage(eL,'Initiate Fixation...'); ... %status text on the eyelink
	@()enableFlip(obj); 
	@()resetFixation(eL); ...
	@()setOffline(eL); ... %make sure offline before start recording
	@()edit(obj.stimuli,6,'colourOut',[1 1 0]); ...
	@()show(obj.stimuli); ...
	@()edfMessage(eL,'V_RT MESSAGE END_FIX END_RT'); ...
	@()edfMessage(eL,['TRIALID ' num2str(getTaskIndex(obj))]); ...
	@()edfMessage(eL,['UUID ' UUID(sM)]); ...
	@()startRecording(eL); ... %fire up eyelink
	@()sendTTL(io,3); ...
	@()syncTime(eL); ... %EDF sync message
	@()draw(obj.stimuli); ... %draw stimulus
	};

%fix within
fixFcn = { @()draw(obj.stimuli) }; %draw stimulus

%test we are fixated for a certain length of time
initFixFcn = @()testSearchHoldFixation(eL,'stimulus','incorrect');

%exit fixation phase
fixExitFcn = { @()animate(obj.stimuli); ... % animate stimuli for subsequent draw
	@()updateFixationTarget(obj, tS.useTask, targetFixInit, targetFixTime, targetRadius, strict); ... %use our stimuli values for next fix X and Y
	@()updateFixationValues(eL, [], [], targetFixInit, targetFixTime, targetRadius, strict); ... %set target fix window
	@()statusMessage(eL,'Show Stimulus...'); ...
	@()edit(obj.stimuli,6,'colourOut',[0.65 0.65 0.45]); ... %dim fix spot
	@()edfMessage(eL,'END_FIX'); ...
	}; 

%what to run when we enter the stim presentation state
stimEntryFcn = @()doStrobe(obj,true);

%what to run when we are showing stimuli
stimFcn =  { @()draw(obj.stimuli); ...	@()drawEyePosition(eL); ...
	@()finishDrawing(s); ...
	@()animate(obj.stimuli); ... % animate stimuli for subsequent draw
	};

%test we are maintaining fixation
maintainFixFcn = @()testSearchHoldFixation(eL,'correct','breakfix');

%as we exit stim presentation state
stimExitFcn = { @()setStrobeValue(obj,inf); @()doStrobe(obj,true) };

%if the subject is correct (small reward)
correctEntryFcn = { @()timedTTL(lJ,0,tS.rewardTime); ... % labjack sends a TTL to Crist reward system
	@()sendTTL(io,4); ...
	@()edfMessage(eL,'END_RT'); ...
	@()statusMessage(eL,'Correct! :-)'); ...
	@()drawTimedSpot(s, 0.5, [0 1 0 1]); ...
	@()hide(obj.stimuli{6}); ...
	@()stopRecording(eL); ...
	@()edfMessage(eL,'TRIAL_RESULT 1'); ...
	};

%correct stimulus
correctFcn = { @()draw(obj.stimuli); 
	@()drawTimedSpot(s, 0.5, [0 1 0 1]); ...
	};

%when we exit the correct state
correctExitFcn = {
	@()setOffline(eL); ... %set eyelink offline
	@()updateVariables(obj,[],[],true); ... %randomise our stimuli, set strobe value too
	@()update(obj.stimuli); ... %update our stimuli ready for display
	@()getStimulusPositions(obj.stimuli); ... %make a struct the eL can use for drawing stim positions
	@()updateFixationValues(eL, fixX, fixY, firstFixInit, firstFixTime, firstFixRadius, strict); ...
	@()trackerClearScreen(eL); ... 
	@()trackerDrawFixation(eL); ... %draw fixation window on eyelink computer
	@()trackerDrawStimuli(eL,obj.stimuli.stimulusPositions); ... %draw location of stimulus on eyelink
	@()drawTimedSpot(s, 0.5, [0 1 0 1], 0.2, true); ... %reset the timer on the green spot
	@()updatePlot(bR, eL, sM); ... %update our behavioural plot
	};
%incorrect entry
incEntryFcn = { @()statusMessage(eL,'Incorrect :-('); ... %status message on eyelink
	@()sendTTL(io,6); ...
	@()edfMessage(eL,'END_RT'); ...
	@()stopRecording(eL); ...
	@()edfMessage(eL,'TRIAL_RESULT 0'); ...
	@()hide(obj.stimuli{6}); ...
	}; 

%our incorrect stimulus
incFcn = @()draw(obj.stimuli);

%incorrect / break exit
incExitFcn = { 
	@()setOffline(eL); ... %set eyelink offline
	@()updateVariables(obj,[],[],false); ...
	@()update(obj.stimuli); ... %update our stimuli ready for display
	@()getStimulusPositions(obj.stimuli); ... %make a struct the eL can use for drawing stim positions
	@()updateFixationValues(eL, fixX, fixY, firstFixInit, firstFixTime, firstFixRadius, true); ...
	@()trackerClearScreen(eL); ... 
	@()trackerDrawFixation(eL); ... %draw fixation window on eyelink computer
	@()trackerDrawStimuli(eL,obj.stimuli.stimulusPositions); ... %draw location of stimulus on eyelink
	@()updatePlot(bR, eL, sM); ... %update our behavioural plot;
	};

%break entry
breakEntryFcn = { @()statusMessage(eL,'Broke Fixation :-('); ...%status message on eyelink
	@()sendTTL(io,5);
	@()edfMessage(eL,'END_RT'); ...
	@()stopRecording(eL); ...
	@()edfMessage(eL,'TRIAL_RESULT -1'); ...
	@()hide(obj.stimuli{6}); ...
	};

%calibration function
calibrateFcn = { @()setOffline(eL); @()rstop(io); @()trackerSetup(eL) }; %enter tracker calibrate/validate setup mode

%debug override
overrideFcn = @()keyOverride(obj); %a special mode which enters a matlab debug state so we can manually edit object values

%screenflash
flashFcn = @()flashScreen(s, 0.2); % fullscreen flash mode for visual background activity detection

%show 1deg size grid
gridFcn = @()drawGrid(s);

sM.skipExitStates = {'fixate','incorrect|breakfix'};

%----------------------State Machine Table-------------------------
disp('================>> Building state info file <<================')
%specify our cell array that is read by the stateMachine
stateInfoTmp = { ...
'name'      'next'		'time'  'entryFcn'		'withinFcn'		'transitionFcn'	'exitFcn'; ...
'pause'		'prefix'	inf		pauseEntryFcn	[]				[]				pauseExitFcn; ...
'prefix'	'fixate'	1.75	prefixEntryFcn	prefixFcn		[]				[]; ...
'fixate'	'incorrect'	1.4	 	fixEntryFcn		fixFcn			initFixFcn		fixExitFcn; ...
'stimulus'  'incorrect'	1.5		stimEntryFcn	stimFcn			maintainFixFcn	stimExitFcn; ...
'incorrect'	'prefix'	1.25	incEntryFcn		incFcn			[]				incExitFcn; ...
'breakfix'	'prefix'	1.25	breakEntryFcn	incFcn			[]				incExitFcn; ...
'correct'	'prefix'	0.25	correctEntryFcn	correctFcn		[]				correctExitFcn; ...
'calibrate' 'pause'		0.5		calibrateFcn	[]				[]				[]; ...
'override'	'pause'		0.5		overrideFcn		[]				[]				[]; ...
'flash'		'pause'		0.5		flashFcn		[]				[]				[]; ...
'showgrid'	'pause'		10		[]				gridFcn			[]				[]; ...
};

disp(stateInfoTmp)
disp('================>> Loaded state info file  <<================')
clear pauseEntryFcn fixEntryFcn fixFcn initFixFcn fixExitFcn stimFcn maintainFixFcn incEntryFcn ...
	incFcn incExitFcn breakEntryFcn breakFcn correctEntryFcn correctFcn correctExitFcn ...
	calibrateFcn overrideFcn flashFcn gridFcn
