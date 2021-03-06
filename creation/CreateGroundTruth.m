
% -- PARMETERS TO SET

% basePath = 'N:\GroundTruth\';
% filename = '20141202_all';
% outputTag = 'GT';
% MyCells = [1099, 1002, 1014, 545, 1034, 1328, 1171];

% basePath = 'N:\Warburg\20150924\';
% filename = '20150924_1';
basePath = 'J:\Warburg\20150924\';
filename = '20150924_1_fix';
outputTag = 'GT';
MyCells = [1256, 1259, 1260, 1269, 1275, 1283, 1285];

% basePath = 'N:\M150218_NS1LAV\';
% filename = '20150601_all';
% outputTag = 'GT';
% MyCells = [4 38 47 136 243 297 883 941];

ActuallyMakeOutput = true; % you can put this to false if you're just testing SVD or whatever
outputToEmpty = false; % This will make an empty file with a little noise to put the spikes into, rather than the original
useStaticSpikes = false; % This will insert the mean waveform at all of the spike times rather than the SVD reconstructed spikes

nChansInRawFile = 128; % in the file, total, including non-neural

nSVDs = 6; % to use in the reconstruction

tBefore = 10; % samples before the spike time to include in the waveforms that will be SVD'd
tAfter = 50;
TotChans = 128; % not including sync pulse!

JitterSize = 20*25; % add this much triangular-distributed jitter to spike samples

Thresh = -30; % determines which channels to include as part of this neuron

% -- END EDITABLE PARAMETERS

KwikFile = [basePath filename '.kwik'];
DatFile = [basePath filename '.dat'];
OutputFile = [basePath filename '_' outputTag '.dat'];
% chanMap = imecChanMap();
% load('forPRBimecToWhisper.mat'); % gives "chanMap" and "connected"
chanMap = 1:128; connected = true(1,128);


fprintf('Loading spike times...');
Clu = h5read(KwikFile, '/channel_groups/1/spikes/clusters/main');
TimeSamples = h5read(KwikFile, '/channel_groups/1/spikes/time_samples');
Res = uint64(TimeSamples);

% % Uncomment this if there was more than one file combined; will need to
% % revise if there are more than 2. 
% Recording = h5read(KwikFile, '/channel_groups/1/spikes/recording');
% FirstFileSize = uint64(h5readatt(KwikFile, '/recordings/1/', 'start_sample'));
% Res = uint64(TimeSamples) + uint64(Recording)*FirstFileSize; % actual time into file







nT = tBefore+tAfter+1;



if ActuallyMakeOutput && ~outputToEmpty
    fprintf('Copying file...');

    copyfile(DatFile, OutputFile);
    fprintf('done\n');
elseif outputToEmpty
    fprintf('Writing blank file...');
    FileInf = dir(DatFile);
    
    fid = fopen(OutputFile, 'w');
    chunkSize = 25000*10*nChansInRawFile;
    for d = 1:floor(FileInf.bytes/2/chunkSize)
        fwrite(fid, int16(20*randn([1 chunkSize])), 'int16');
    end
    fwrite(fid, zeros([1 FileInf.bytes/2-floor(FileInf.bytes/2/chunkSize)*chunkSize],'int16'), 'int16');
    
    fclose(fid);
    fprintf('done\n');

%     fprintf('Copying file...');
% 
%     copyfile([basePath 'blank.dat'], OutputFile);
%     fprintf('done\n');

end
    
    
    
FileInf = dir(DatFile);
Source = memmapfile(DatFile, 'Format', {'int16', [nChansInRawFile, (FileInf.bytes/nChansInRawFile/2)], 'x'});
Target = memmapfile(OutputFile, 'Format', {'int16', [nChansInRawFile, (FileInf.bytes/nChansInRawFile/2)], 'x'}, 'Writable', true);

clear gtTimes Chans gtChans
%%
for c=1:length(MyCells)
%     close all
    MyCell = MyCells(c);
    fprintf('cell %d: ', MyCell);
    MyTimes = Res(find(Clu==MyCell));%FileBase ='\\zserver.ioo.ucl.ac.uk\Data\multichanspikes\M140528_NS1\20141202\20141202_all';

    nSpikes = length(MyTimes);
    
    spikeLimit = 25000;
    if nSpikes >spikeLimit
        q = randperm(nSpikes);
        MyTimes = MyTimes(q(1:spikeLimit));
        nSpikes = spikeLimit;
    end
    
    

% load in spike waveforms 
    fprintf('loading ... ');
    FullSpikes = zeros(TotChans, nT, nSpikes);
    for i=1:nSpikes
        FullSpikes(:,:,i) = Source.Data.x(1:TotChans,MyTimes(i)-tBefore:MyTimes(i)+tAfter);
    end
    
    % zero-out the unconnected channels here 
    FullSpikes(chanMap(~connected),:,:) = 0;

    fprintf('computing ... ');
    % compute mean spike and get channels by thresholding
    FullMeanSpike = mean(FullSpikes,3);
    FullMeanSpike0 = bsxfun(@minus,FullMeanSpike,FullMeanSpike(:,1));
    figure;
    subplot(1,2,1); imagesc(FullMeanSpike0(chanMap,:)); 
    title('Mean spike');
    subplot(1,2,2); imagesc(FullMeanSpike0(chanMap,:)<Thresh); 
    title(sprintf('Threshold %d', Thresh));
    MyChans = find(any(FullMeanSpike0<Thresh,2));
    Chans{c} = MyChans;
    nChans = length(MyChans);
    % find right order to display channels
    RevPerm(chanMap) = 1:TotChans;
    [~,MyChanOrder] = sort(RevPerm(MyChans));


    % now create subarray for just appropriate channels
    % MySpikes(nChans, nSamples, nSpikes)
    MySpikes = FullSpikes(MyChans,:,:);


    % Detrend it: dMySpikes starts and ends at 0, ddMySpikes is its diff
    MySpikes0 = bsxfun(@minus, MySpikes, MySpikes(:,1,:));
    dMySpikes = MySpikes0 - bsxfun(@times, MySpikes0(:,end,:), (0:nT-1)/(nT-1));
    ddMySpikes = diff(dMySpikes, 1, 2);

    % plot mean detrended waveform
    figure;
    MeanSpike = mean(dMySpikes,3);
    imagesc(MeanSpike(MyChanOrder,:));
    title('Detrended spike on suprathreshold channels');

    if useStaticSpikes
        ReconSpikes = repmat(MeanSpike, [1 1 size(FullSpikes,3)]);
    else
        % now do the SVD on the derivative
        FlatSpikes = reshape(ddMySpikes, [nChans*(nT-1), nSpikes]);
        [u s v]=svd(FlatSpikes,0);

        % and reconstruct them from from the cumsum of the svd approximation
        FlatReconSpikes = u(:,1:nSVDs)*s(1:nSVDs, 1:nSVDs)*v(:,1:nSVDs)';
        ReconSpikes = [zeros(nChans, 1, nSpikes), cumsum(reshape(FlatReconSpikes, [nChans, nT-1, nSpikes]),2)];
    end

    % Show reconstruction quality
    figure
    Offsets =  repmat(300*(1:nChans)',[1 nT]);
    % Colors = colorcube(nChans+3);
    % set(gca, 'colororder', Colors(1:nChans,:));
    for i=1:8
        subplot(2,4,i); cla; hold on
    %     subplot(1,2,1)
        q = randi(size(dMySpikes,3),1);
        plot(dMySpikes(:,:,q)'+Offsets');
         ylim([-500 300*(nChans+1)]);
    %     subplot(1,2,2)
        ax = gca;
        ax.ColorOrderIndex = 1;
        plot(ReconSpikes(:,:,q)'+Offsets', 'k');
        ylim([-500 300*(nChans+1)]);
        drawnow
    end

    
    if ActuallyMakeOutput
        fprintf('writing ...');
        % now add to the ground truth file
        if all(RevPerm(MyChans)<108) 
            ChanShift = 20;
        else
            ChanShift = -20;
        end
        TargetChans = chanMap(RevPerm(MyChans)+ChanShift);

        
        gtTimes{c} = round(randn(nSpikes,1)*JitterSize) + double(MyTimes);
        gtTimes{c}(gtTimes{c}<(tBefore+2)) = -gtTimes{c}(gtTimes{c}<tBefore+2);
        gtTimes{c}(gtTimes{c}>Target.Format{2}(2)-tAfter-2) = Target.Format{2}(2)- (gtTimes{c}(gtTimes{c}>Target.Format{2}(2)-tAfter-2)-Target.Format{2}(2));
        for i=1:nSpikes
            tRange = gtTimes{c}(i)-tBefore : gtTimes{c}(i)+tAfter;
            
            %Target.Data.x(TargetChans,tRange) = double(Source.Data.x(TargetChans,tRange)) + ReconSpikes(:,:,i);
            Target.Data.x(TargetChans,tRange) = double(Target.Data.x(TargetChans,tRange)) + ReconSpikes(:,:,i); % fixed by NS 2015/11/3
        end
        gtChans{c} = TargetChans;
        
    end
    fprintf('done\n');
    clear FullSpikes v ReconSpikes MySpikes MySpikes0 FlatSpikes FlatReconSpikes dMySpikes ddMySpikes s u
    
end

%%
clear Source Target
save([basePath filename '_' outputTag '_gtTimes'], 'gtTimes', 'gtChans');

gtClu = []; gtRes = [];
for c=1:length(MyCells)
    gtRes = [gtRes; gtTimes{c}];
    gtClu = [gtClu; (c+1)*ones(size(gtTimes{c}))];
    
end
[~,order] = sort(gtRes, 'ascend');

SaveClu([basePath filename '_' outputTag '.clu.1'], gtClu(order));
dlmwrite([basePath filename '_' outputTag '.res.1'], gtRes(order), 'precision', '%d');

fprintf(1, 'complete \n');