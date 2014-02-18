classdef LFPAnalysis < optickaCore
%LFPAnalysis Wraps the native and fieldtrip analysis around our PLX/PL2 reading.
	
	properties
		lfpfile@char
		spikefile@char
		dir@char
		doLFP@logical = false
		demeanLFP@logical = true
		selectedLFP@double = 1
		LFPWindow@double = 0.7
		verbose	= true
	end
	
	properties (SetAccess = private, GetAccess = public)
		p@plxReader
		pspike@plxReader
		LFPs@struct
		ft@struct
		cutTrials@cell
		clickedTrials@cell
		nLFPs@double = 0
		map
	end
	
	properties (SetAccess = private, GetAccess = private)
		oldDir@char
		%> allowed properties passed to object upon construction
		allowedProperties@char = 'file|dir|matfile|matdir|edffile|startOffset|cellmap|verbose|doLFP'
	end
	
	%=======================================================================
	methods %------------------PUBLIC METHODS
	%=======================================================================

		% ===================================================================
		%> @brief Constructor
		%>
		%> @param varargin
		%> @return
		% ===================================================================
		function ego = LFPAnalysis(varargin)
			if nargin == 0; varargin.name = 'LFPAnalysis';end
			if nargin>0; ego.parseArgs(varargin, ego.allowedProperties); end
			if isempty(ego.name);ego.name = 'LFPAnalysis'; end
			getFiles(ego, true);
		end
		
		% ===================================================================
		%> @brief Constructor
		%>
		%> @param varargin
		%> @return
		% ===================================================================
		function getFiles(ego,force)
			if ~exist('force','var')
				force = false;
			end
			if force == true || isempty(ego.lfpfile)
				[f,p] = uigetfile({'*.plx;*.pl2';'Plexon Files'},'Load LFP File');
				if ischar(f) && ~isempty(f)
					ego.lfpfile = f;
					ego.dir = p;
					ego.paths.oldDir = pwd;
					cd(ego.dir);
					ego.p = plxReader('file', ego.lfpfile, 'dir', ego.dir);
					getFiles(ego.p);
				else
					return
				end
			end
			if force == true || isempty(ego.spikefile)
				[f,p] = uigetfile({'*.plx;*.pl2';'Plexon Files'},'Load Spike File');
				if ischar(f) && ~isempty(f)
					ego.spikefile = f;
					ego.pspike = plxReader('file', ego.spikefile, 'dir', ego.dir);
					ego.pspike.matfile = ego.p.matfile;
					ego.pspike.matdir = ego.p.matdir;
					ego.pspike.edffile = ego.p.edffile;
				else
					return
				end
			end
		end
		
		% ===================================================================
		%> @brief
		%>
		%> @param
		%> @return
		% ===================================================================
		function loadLFPs(ego)
			if isempty(ego.lfpfile)
				getFiles(ego,true);
				if isempty(ego.lfpfile);return;end
			end
			ego.mversion = str2double(regexp(version,'(?<ver>^\d\.\d[\d]?)','match','once'));
			if ego.mversion < 8.2
				error('LFP Analysis requires Matlab >= 2013b!!!')
			end
			ego.paths.oldDir = pwd;
			cd(ego.dir);
			ego.LFPs = readLFPs(ego.p, ego.LFPWindow, ego.demeanLFP);
			ego.ft = struct();
			parseLFPs(ego);
			plotLFPs(ego);
			ft_parseLFPs(ego);
		end
		
		% ===================================================================
		%> @brief
		%>
		%> @param
		%> @return
		% ===================================================================
		function ft = ft_parseLFPs(ego)
			ft_defaults;
			tic
			ft = struct();
			ft(1).hdr = ft_read_plxheader(ego.lfpfile);
			ft.label = {ego.LFPs(:).name};
			ft.time = cell(1);
			ft.trial = cell(1);
			ft.fsample = 1000;
			ft.sampleinfo = [];
			ft.trialinfo = [];
			ft.cfg = struct;
			ft.cfg.dataset = ego.lfpfile;
			ft.cfg.headerformat = 'plexon_plx_v2';
			ft.cfg.dataformat = ft.cfg.headerformat;
			ft.cfg.eventformat = ft.cfg.headerformat;
			ft.cfg.trl = [];
			a=1;
			for j = 1:length(ego.LFPs(1).vars)
				for k = 1:ego.LFPs(1).vars(j).nTrials
					ft.time{a} = ego.LFPs(1).vars(j).trial(k).time';
					for i = 1:length(ego.LFPs)
						dat(i,:) = ego.LFPs(i).vars(j).trial(k).data';
					end
					ft.trial{a} = dat;
					window = ego.LFPs(1).vars(j).trial(k).winsteps;
					ft.sampleinfo(a,1)= ego.LFPs(1).vars(j).trial(k).startIndex-window;
					ft.sampleinfo(a,2)= ego.LFPs(1).vars(j).trial(k).startIndex+window;
					ft.cfg.trl(a,:) = [ft.sampleinfo(a,:) -window];
					ft.trialinfo(a,1) = j;
					a = a+1;
				end
			end
			ft.uniquetrials = unique(ft.trialinfo);
	
			fprintf('Parsing into fieldtrip format took %g ms\n',round(toc*1000));
			
			if ~isempty(ft)
				ego.ft = ft;
			end
		end
		
		% ===================================================================
		%> @brief
		%>
		%> @param
		%> @return
		% ===================================================================
		function ftPreProcess(ego,cfg)
			if isempty(ego.ft); ft_parseLFPs(ego); end
			if isfield(ego.ft,'ftOld')
				ft = ego.ft.ftOld;
			else
				ft = ego.ft;
			end
			if ~exist('cfg','var')
				cfg = [];
			else %assume we want to do some preprocessing
				ftp = ft_preprocessing(cfg,ft);
				ftp.uniquetrials = unique(ftp.trialinfo);
			end
			cfg.method   = 'trial';
			ftNew = ft_rejectvisual(cfg,ft);
			ftNew.uniquetrials = unique(ftNew.trialinfo);
			ftNew.ftOld = ft;
			ego.ft = ftNew;
		end
		
		% ===================================================================
		%> @brief
		%>
		%> @param
		%> @return
		% ===================================================================
		function cfg=ftTimeLockAnalysis(ego,cfg)
			ft = ego.ft;
			if ~exist('cfg','var')
				cfg = [];
				cfg.keeptrials = 'yes';
				cfg.removemean = 'yes';
				cfg.covariance = 'yes';
				cfg.covariancewindow = [0.075 0.2];
				cfg.channel = ft.label{ego.selectedLFP};
			end
			for i = ft.uniquetrials'
				cfg.trials = find(ft.trialinfo == i);
				av{i} = ft_timelockanalysis(cfg,ft);
				av{i}.cfgUsed = cfg;
				if strcmpi(cfg.covariance,'yes')					
					disp(['-->> Covariance for Var:' num2str(i) ' = ' num2str(mean(av{i}.cov))]);
				end
			end		
			ego.ft.av = av;
			drawAverageLFPs(ego);
		end
		
		% ===================================================================
		%> @brief
		%>
		%> @param
		%> @return
		% ===================================================================
		function cfgUsed=ftFrequencyAnalysis(ego,cfg,preset,tw,cycles,width,smth)
			if ~exist('preset','var') || isempty(preset); preset='fix1'; end
			if ~exist('tw','var') || isempty(tw); tw=0.2; end
			if ~exist('cycles','var') || isempty(cycles); cycles = 5; end
			if ~exist('width','var') || isempty(width); width = 10; end
			if ~exist('smooth','var') || isempty(smth); smth = 10; end
			ft = ego.ft;
			cfgUsed = {};
			if ~exist('cfg','var') || isempty(cfg)
				cfg				= [];
				cfg.keeptrials	= 'yes';
				cfg.output		= 'pow';
				cfg.channel = ft.label{ego.selectedLFP};
				cfg.toi         = -0.4:0.02:0.4;                  % time window "slides"
				cfg.tw = tw;
				cfg.cycles = cycles;
				cfg.width = width;
				cfg.smooth = smth;
				switch preset
					case 'fix1'
						cfg.method      = 'mtmconvol';
						cfg.taper		= 'hanning';
						lf = round(1 / cfg.tw);
						cfg.foi         = lf:2:80;						  % analysis frequencies 
						cfg.t_ftimwin  = ones(length(cfg.foi),1).*tw;   % length of fixed time window
					case 'fix2'
						cfg.method      = 'mtmconvol';
						cfg.taper        = 'hanning';
						cfg.foi         = 2:2:80;						  % analysis frequencies 
						cfg.t_ftimwin	= cycles./cfg.foi;					  % x cycles per time window
					case 'mtm1'
						cfg.method      = 'mtmconvol';
						cfg.taper       = 'dpss';
						cfg.foi         = 2:2:80;						  % analysis frequencies 
						cfg.tapsmofrq	= cfg.foi * cfg.smooth;
						cfg.t_ftimwin	= cycles./cfg.foi;					  % x cycles per time window
					case 'mtm2'
						cfg.method      = 'mtmconvol';
						cfg.taper       = 'dpss';
						cfg.foi         = 2:2:80;						  % analysis frequencies 
					case 'morlet'
						cfg.method		= 'wavelet';
						cfg.taper		= '';
						cfg.width		= width;
						cfg.foi         = 2:2:80;						  % analysis frequencies 
				end
			elseif ~isempty(cfg)
				preset = 'custom';
			end
			for i = ft.uniquetrials'
				cfg.trials = find(ft.trialinfo == i);
				fq{i} = ft_freqanalysis(cfg,ft);
				fq{i}.cfgUsed=cfg;
				cfgUsed{i} = cfg;
			end
			ego.ft.(['fq' preset]) = fq;
			drawLFPFrequencies(ego,['fq' preset]);
		end
		
		% ===================================================================
		%> @brief
		%>
		%> @param
		%> @return
		% ===================================================================
		function cfgUsed=ftSpikeLFP(ego,cfg)
			if ~exist('preset','var') || isempty(preset); preset='fix1'; end
			if ~exist('tw','var') || isempty(tw); tw=0.2; end
			if ~exist('cycles','var') || isempty(cycles); cycles = 5; end
			if ~exist('width','var') || isempty(width); width = 10; end
			if ~exist('smooth','var') || isempty(smth); smth = 10; end
			ft = ego.ft;
			cfgUsed = {};
			if ~exist('cfg','var') || isempty(cfg)
				cfg				= [];
				cfg.keeptrials	= 'yes';
				cfg.output		= 'pow';
				cfg.channel = ft.label{ego.selectedLFP};
				cfg.toi         = -0.4:0.02:0.4;                  % time window "slides"
				cfg.tw = tw;
				cfg.cycles = cycles;
				cfg.width = width;
				cfg.smooth = smth;
				switch preset
					case 'fix1'
						cfg.method      = 'mtmconvol';
						cfg.taper		= 'hanning';
						lf = round(1 / cfg.tw);
						cfg.foi         = lf:2:80;						  % analysis frequencies 
						cfg.t_ftimwin  = ones(length(cfg.foi),1).*tw;   % length of fixed time window
					case 'fix2'
						cfg.method      = 'mtmconvol';
						cfg.taper        = 'hanning';
						cfg.foi         = 2:2:80;						  % analysis frequencies 
						cfg.t_ftimwin	= cycles./cfg.foi;					  % x cycles per time window
					case 'mtm1'
						cfg.method      = 'mtmconvol';
						cfg.taper       = 'dpss';
						cfg.foi         = 2:2:80;						  % analysis frequencies 
						cfg.tapsmofrq	= cfg.foi * cfg.smooth;
						cfg.t_ftimwin	= cycles./cfg.foi;					  % x cycles per time window
					case 'mtm2'
						cfg.method      = 'mtmconvol';
						cfg.taper       = 'dpss';
						cfg.foi         = 2:2:80;						  % analysis frequencies 
					case 'morlet'
						cfg.method		= 'wavelet';
						cfg.taper		= '';
						cfg.width		= width;
						cfg.foi         = 2:2:80;						  % analysis frequencies 
				end
			elseif ~isempty(cfg)
				preset = 'custom';
			end
			for i = ft.uniquetrials'
				cfg.trials = find(ft.trialinfo == i);
				fq{i} = ft_freqanalysis(cfg,ft);
				fq{i}.cfgUsed=cfg;
				cfgUsed{i} = cfg;
			end
		end
		
		% ===================================================================
		%> @brief 
		%>
		%> @param
		%> @return
		% ===================================================================
		function plotLFPs(ego,varargin)
			if isempty(ego.LFPs);
				return
			end
			if isempty(varargin) || ~ischar(varargin{1})
				sel = 'normal';
			else
				sel = varargin{1};
			end
			
			if length(varargin) > 1
				args = varargin(2:end);
			else
				args = {};
			end
			
			switch sel
				case 'normal'
					ego.drawAllLFPs(); drawnow;			
					ego.drawRawLFPs(); drawnow;		
					ego.drawAverageLFPs(); drawnow;
				case 'all'
					ego.drawAllLFPs(true);			
					ego.drawRawLFPs();		
					ego.drawAverageLFPs();
				case 'continuous'
					ego.drawAllLFPs(true); drawnow;
				case {'trials','raw'}
					ego.drawRawLFPs(); drawnow;
				case 'average'
					ego.drawAverageLFPs(); drawnow;
				case 'frequency'
					ego.drawLFPFrequencies(args); drawnow;
			end
		end
		
	end

	%=======================================================================
	methods ( Access = private ) %-------PRIVATE METHODS-----%
	%=======================================================================
	
		% ===================================================================
		%> @brief 
		%>
		%> @param
		%> @return
		% ===================================================================
		function LFPs = parseLFPs(ego)
			
			LFPs = ego.LFPs;
			if isempty(LFPs)
				LFPs = readLFPs(ego.p);
			end
			cuttrials = '{ ';
			if isempty(ego.cutTrials) || length(ego.cutTrials) < LFPs(1).nVars
				for i = 1:LFPs(1).nVars
					cuttrials = [cuttrials ''''', '];
				end
			else
				if isempty(cell2mat(ego.clickedTrials))
					for i = 1:length(ego.cutTrials)
						cuttrials = [cuttrials '''' num2str(ego.cutTrials{i}) ''', '];
					end
				else
					for i = 1:length(ego.clickedTrials)
						cuttrials = [cuttrials '''' num2str(ego.clickedTrials{i}) ''', '];
					end
				end
			end
			cuttrials = cuttrials(1:end-2);
			cuttrials = [cuttrials ' }'];
			
			map = cell(1,3);
			if isempty(ego.map) || length(ego.map)~=3 || ~iscell(ego.map)
				map{1} = '1 2 3 4 5 6';
				map{2} = '7 8';
				map{3} = '';
			else
				map{1} = num2str(ego.map{1});
				map{2} = num2str(ego.map{2});
				map{3} = num2str(ego.map{3});
			end
			
			sel = num2str(ego.selectedLFP);
			
			options.Resize='on';
			options.WindowStyle='normal';
			options.Interpreter='tex';
			prompt = {'Choose PLX variables to merge (ground):','Choose PLX variables to merge (figure):','Choose PLX variables to merge (figure 2):','Enter Trials to exclude','Choose which LFP channel to select'};
			dlg_title = ['REPARSE ' num2str(LFPs(1).nVars) ' DATA VARIABLES'];
			num_lines = [1 120];
			def = {map{1}, map{2}, map{3}, cuttrials,sel};
			answer = inputdlg(prompt,dlg_title,num_lines,def,options);
			drawnow;
			if isempty(answer)
				map{1} = []; map{2}=[]; map{3}=[]; cuttrials = {''};
			else
				map{1} = str2num(answer{1}); map{2} = str2num(answer{2}); map{3} = str2num(answer{3}); 
				if ~isempty(answer{4}) && strcmpi(answer{4}(1),'{')
					ego.cutTrials = eval(answer{4});
				else
					ego.cutTrials = {''};
				end
				ego.map = map;
				ego.selectedLFP = str2num(answer{5});
				if ego.selectedLFP < 1 || ego.selectedLFP > length(LFPs)
					ego.selectedLFP = 1;
				end
			end
			
			if ~isempty(map{1}) && ~isempty(map{2})
				tic

				for j = 1:length(LFPs)
					
					vars = LFPs(j).vars;
					nvars = vars(1);
					nvars(1).times = [];
					nvars(1).nTrials = 0;
					nvars(1).trial = [];
					nvars(1).time = [];
					nvars(1).alldata = [];
					nvars(1).average = [];
					nvars(1).error = [];
					nvars(1).minL = [];
					nvars(1).maxL = [];
					vartemplate = nvars(1);
					
					if isempty(map{3})
						repn=[1 2];
						nvars(2) = vartemplate;
					else
						repn = [1 2 3];
						nvars(2) = vartemplate;
						nvars(3) = vartemplate;
					end
					
					for n = repn
						for k = 1:length(map{n})
							thisVar = map{n}(k);
							if (length(ego.cutTrials) >= thisVar) && ~isempty(ego.cutTrials{thisVar}) %trial removal
								cut = str2num(ego.cutTrials{thisVar});
								vars(thisVar).times(cut,:) = [];
								vars(thisVar).alldata(:,cut) = [];
								vars(thisVar).trial(cut) = [];
								vars(thisVar).nTrials = length(vars(thisVar).trial);
								[vars(thisVar).average, vars(thisVar).error] = stderr(vars(thisVar).alldata');
							end
							nvars(n).times = [nvars(n).times;vars(thisVar).times];
							nvars(n).nTrials = nvars(n).nTrials + vars(thisVar).nTrials;
							nvars(n).trial = [nvars(n).trial, vars(thisVar).trial];
							nvars(n).alldata = [nvars(n).alldata, vars(thisVar).alldata];
						end
						nvars(n).time = vars(1).time;
						[nvars(n).average, nvars(n).error] = stderr(nvars(n).alldata');
						nvars(n).minL = vars(1).minL;
						nvars(n).maxL = vars(1).maxL;
					
					end
					LFPs(j).oldvars = LFPs(j).vars;
					LFPs(j).vars = nvars;
					LFPs(j).nVars = length(LFPs(j).vars);
					LFPs(j).reparse = true;
				end
				fprintf('Reparsing LFP variables took %g ms\n',round(toc*1000));
			end
			
			if ~isempty(LFPs(1).vars)
				ego.LFPs = LFPs;
				ego.nLFPs = length(LFPs);
			end	
		end
		
		% ===================================================================
		%> @brief
		%>
		%> @param
		%> @return
		% ===================================================================
		function h=drawRawLFPs(ego,h,sel)
			disp('Drawing RAW LFP Trials...')
			if ~exist('h','var')
				h=figure;figpos(1,[1920 1080]);set(h,'Color',[1 1 1]);
				ego.clickedTrials = cell(1,ego.LFPs(1).nVars);
			end
			clf(h,'reset')
			if ~exist('sel','var')
				sel= ego.selectedLFP;
			end

			LFPs = ego.LFPs;

			p=panel(h);
			len=length(LFPs(sel).vars);
			if len < 3
				row = 2;
				col = 1;
			elseif len < 4
				row = 3;
				col = 1;
			elseif len < 9
				row=4;
				col=2;
			elseif len < 13
				row = 4;
				col = 3;
			end
			p.pack(row,col);
			for j = 1:length(LFPs(sel).vars)
				[i1,i2] = ind2sub([row,col], j);
				p(i1,i2).select();
				title(['LFP & EVENT PLOT: File:' ego.lfpfile ' | Channel:' LFPs(sel).name ' | Var:' num2str(j)]);
				xlabel('Time (s)');
 				ylabel('LFP Raw Amplitude (mV)');
				hold on
				for k = 1:size(LFPs(1).vars(j).alldata,2)
					dat = [j,k];
					tag=['VAR:' num2str(dat(1)) '  TRL:' num2str(dat(2))];
					if strcmpi(class(gcf),'double')
						c=rand(1,3);
						plot(LFPs(sel).vars(j).time, LFPs(sel).vars(j).alldata(:,k), 'Color', c, 'Tag', tag, 'ButtonDownFcn', @clickMe, 'UserData', dat);
					else
						plot(LFPs(sel).vars(j).time, LFPs(sel).vars(j).alldata(:,k),'Tag',tag,'ButtonDownFcn', @clickMe,'UserData',dat);
					end
				end
				areabar(LFPs(sel).vars(j).time, LFPs(sel).vars(j).average,LFPs(sel).vars(j).error,[0.7 0.7 0.7],0.7,'k-o','MarkerFaceColor',[0 0 0],'LineWidth',1);
				hold off
				axis([-0.1 0.3 -inf inf]);
			end
			dc = datacursormode(gcf);
			set(dc,'UpdateFcn', @lfpCursor, 'Enable', 'on', 'DisplayStyle','window');
			
			uicontrol('Style', 'pushbutton', 'String', '<<',...
				'Position',[1 1 50 20],'Callback',@previousChannel);
			uicontrol('Style', 'pushbutton', 'String', '>>',...
				'Position',[52 1 50 20],'Callback',@nextChannel);

			function nextChannel(src,~)
				ego.selectedLFP = ego.selectedLFP + 1;
				if ego.selectedLFP > length(ego.LFPs)
					ego.selectedLFP = 1;
				end
				drawRawLFPs(ego,gcf,ego.selectedLFP);
			end
			function previousChannel(src,~)
				ego.selectedLFP = ego.selectedLFP - 1;
				if ego.selectedLFP < 1
					ego.selectedLFP = length(ego.LFPs);
				end
				drawRawLFPs(ego,gcf,ego.selectedLFP);
			end
			
			function clickMe(src, ~)
				if ~exist('src','var') || ego.LFPs(ego.selectedLFP).reparse == true
					return
				end
				ud = get(src,'UserData');
				tg = get(src,'Tag');
				disp(['Clicked on: ' tg]);
				if ~isempty(ud) && length(ud) == 2
					var = ud(1);
					trl = ud(2);
					if length(ego.clickedTrials) < var
						ego.clickedTrials{var} = trl;
					else
						if ischar(ego.clickedTrials{var})
							ego.clickedTrials{var} = str2num(ego.clickedTrials{var});
						end
						it = intersect(ego.clickedTrials{var}, trl);
						if ~ischar(it) && isempty(it)
							ego.clickedTrials{var} = [ego.clickedTrials{var}, trl];
						else
							ego.clickedTrials{var}(ego.clickedTrials{var} == it) = [];
						end
					end
					for i = 1:length(ego.clickedTrials)
						disp(['Current Selected trials for Var ' num2str(i) ': ' num2str(ego.clickedTrials{i})]);
					end
				end
				assignin('base','clickedLFP',ego.clickedTrials');
			end
			
		end
		
		% ===================================================================
		%> @brief 
		%>
		%> @param
		%> @return
		% ===================================================================
		function drawAverageLFPs(ego)
			disp('Drawing Averaged (Reparsed) Timelocked LFPs...')
			LFPs = ego.LFPs;
			if LFPs(1).reparse == true;
				for j = 1: length(LFPs)
					figure;figpos(1,[1000 1000]);set(gcf,'Color',[1 1 1]);
					title(['FIGURE vs. GROUND Reparse: File:' ego.lfpfile ' | Channel:' LFPs(j).name ' | LFP:' num2str(j)]);
					xlabel('Time (s)');
					ylabel('LFP Raw Amplitude (mV)');
					hold on
					areabar(LFPs(j).vars(1).time, LFPs(j).vars(1).average,LFPs(j).vars(1).error,[0.7 0.7 0.7],0.6,'k.-','MarkerFaceColor',[0 0 0],'LineWidth',2);
					areabar(LFPs(j).vars(2).time, LFPs(j).vars(2).average,LFPs(j).vars(2).error,[0.7 0.5 0.5],0.6,'r.-','MarkerFaceColor',[1 0 0],'LineWidth',2);
					if length(LFPs(j).vars)>2
						areabar(LFPs(j).vars(3).time, LFPs(j).vars(3).average,LFPs(j).vars(3).error,[0.5 0.5 0.7],0.6,'b-o','MarkerFaceColor',[0 0 1],'LineWidth',2);
						legend('S.E.','Ground','S.E.','Figure','S.E.','Figure 2');
					else
						legend('S.E.','Ground','S.E.','Figure');
					end
					hold off
					axis([-0.1 0.3 -inf inf]);
				end
				if isfield(ego.ft,'av')
					av = ego.ft.av;
					figure;figpos(1,[1000 1000]);set(gcf,'Color',[1 1 1]);
					hold on
					areabar(av{1}.time,av{1}.avg(1,:),av{1}.var(1,:),[.5 .5 .5],'k');
					areabar(av{2}.time,av{2}.avg(1,:),av{2}.var(1,:),[.7 .5 .5],'r');
					if length(av) > 2
						areabar(av{3}.time,av{3}.avg(1,:),av{3}.var(1,:),[.5 .5 .7],'b');
					end
					hold off
					axis([-0.1 0.3 -inf inf]);
					xlabel('Time (s)');
					ylabel('LFP Raw Amplitude (mV)');
					title(['FIELDTRIP TIMELOCK ANALYSIS: File:' ego.lfpfile ' | Channel:' av{1}.label{:} ' | LFP: ']);
				end
			end				
		end
		
		% ===================================================================
		%> @brief 
		%>
		%> @param
		%> @return
		% ===================================================================
		function drawAllLFPs(ego,override)
			if ~exist('override','var'); override = false; end
			if ego.LFPs(ego.selectedLFP).reparse == true && override == false
				return
			end
			disp('Drawing Continuous LFP data...')
			%first plot is the whole raw LFP with event markers
			LFPs = ego.LFPs;
			figure;figpos(1,[2500 800]);set(gcf,'Color',[1 1 1]);
			title(['RAW LFP & EVENT PLOT: File:' ego.lfpfile ' | Channel: All | LFP: All']);
			xlabel('Time (s)');
 			ylabel('LFP Raw Amplitude (mV)');
			hold on
			for j = 1:length(LFPs)
				c=rand(1,3);
				c = c .* 0.75;
				h(j)=plot(LFPs(j).time, LFPs(j).data,'Color',c);
				name{j} = ['LFP ' num2str(j)];
				[av,sd] = stderr(LFPs(j).data,'SD');
				line([LFPs(j).time(1) LFPs(j).time(end)],[av-(2*sd) av-(2*sd)],'Color',get(h(j),'Color'),'LineWidth',2, 'LineStyle','--');
				line([LFPs(j).time(1) LFPs(j).time(end)],[av+(2*sd) av+(2*sd)],'Color',get(h(j),'Color'),'LineWidth',2, 'LineStyle','--');
			end
			axis([0 40 -.5 .5])
			legend(h,name,'Location','NorthWest')
			disp('Drawing Event markers...')
			for j = 1:ego.p.eventList.nVars
				color = rand(1,3);
				var = ego.p.eventList.vars(j);
				for k = 1:length(var.t1correct)
					line([var.t1correct(k) var.t1correct(k)],[-.4 .4],'Color',color,'LineWidth',4);
					line([var.t2correct(k) var.t2correct(k)],[-.4 .4],'Color',color,'LineWidth',4);
					text(var.t1correct(k),.41,['VAR: ' num2str(j) '  TRL: ' num2str(k)]);
				end
			end
			hold off;
			box on;
			pan xon;
			uicontrol('Style', 'pushbutton', 'String', '<<',...
				'Position',[1 1 50 20],'Callback',@backPlot);
			uicontrol('Style', 'pushbutton', 'String', '>>',...
				'Position',[52 1 50 20],'Callback',@forwardPlot);
			
			function forwardPlot(src, ~)
				if ~exist('src','var')
					return
				end
				ax = axis(gca);
				ax(1) = ax(1) + 40;
				ax(2) = ax(1) + 40;
				axis(ax);
			end
			function backPlot(src, ~)
				if ~exist('src','var')
					return
				end
				ax = axis(gca);
				ax(1) = ax(1) - 40;
				ax(2) = ax(1) + 40;
				axis(ax);
			end
		end
		
		% ===================================================================
		%> @brief 
		%>
		%> @param
		%> @return
		% ===================================================================
		function drawLFPFrequencies(ego,name)
			if ~exist('name','var') || isempty(name); name = 'fqfix1'; end
			if ~isfield(ego.ft,name)
				return;
			end
			fq = ego.ft.(name);
			h=figure;figpos(1,[2000 2000]);set(h,'Color',[1 1 1]);
			p=panel(h);
			p.margin = [15 15 30 20];
			p.fontsize = 12;
			len=length(fq);
			if len < 3
				row = 2;
				col = 2;
			elseif len < 4
				row = 3;
				col = 2;
			elseif len < 9
				row=4;
				col=2;
			elseif len < 13
				row = 4;
				col = 3;
			end
			p.pack(row,col);
			bl = {'relative','absolute'};
			for jj = 1:length(bl)
				hmin = inf;
				hmax = -inf;
				h = {};
				for i = 1:len
					p(i,jj).select();
					cfg					= [];
					cfg.fontsize		= 14;
					cfg.baseline		= [-0.2 0];
					cfg.baselinetype	= bl{jj};  
					cfg.interactive		= 'no';
					cfg.channel			= ego.ft.label{ego.selectedLFP};
					cfgOut=ft_singleplotTFR(cfg, fq{i});
					h{i} = gca;
					cfgUsed{i}.plotcfg = cfgOut;
					clim = get(gca,'clim');
					hmin = min([hmin min(clim)]);
					hmax = max([hmax max(clim)]);
					xlabel('Time (s)');
					ylabel('Frequency (Hz)');
					t = [bl{jj} '#' num2str(i) 'Preset: ' name ' | Method: ' fq{i}.cfgUsed.method ' | Taper: ' fq{i}.cfgUsed.taper];
					t = [t ' | Window: ' num2str(fq{i}.cfgUsed.tw) ' | Cycles: ' num2str(fq{i}.cfgUsed.cycles)];
					t = [t ' | Width: ' num2str(fq{i}.cfgUsed.width) ' | Smooth: ' num2str(fq{i}.cfgUsed.smooth)];
					title(t,'FontSize',cfg.fontsize);
				end
				for i = 1:length(h); 
					set(h{i},'clim', [hmin hmax]);
					box on; grid on;
				end
			end
		end
		
	end
end