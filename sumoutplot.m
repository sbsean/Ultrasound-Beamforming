clear; close all; clc;

% -------------------------------------------------------------------------
% 사용자 설정
% -------------------------------------------------------------------------
dataDir    = 'Angle_Sumout_Data';  % 데이터 폴더 경로
numAngles  = 5;                    % 불러올 각도 수 (1~5)
frameNum   = 1;                    % 몇 번째 프레임을 불러올 것인지
dB_min     = -60;                  % 로그 압축 시각화 최소 dB (예: -60 dB)
dB_max     = 0;                    % 로그 압축 시각화 최대 dB (예: 0 dB)
cmap       = 'gray';               % 컬러맵 (흑백: 'gray', 등)
% -------------------------------------------------------------------------

figure('Name','Angle Sumout Envelope Plots (Single Row)','NumberTitle','off');

for n = 1:numAngles
    % ---------------------------------------------------------------------
    % 1) 파일 이름 및 경로 생성
    %    예: 'Angle_sumout01degree_001frame.mat'
    % ---------------------------------------------------------------------
    fileName = sprintf('Angle_sumout%02ddegree_%03dframe.mat', n, frameNum);
    fullPath = fullfile(dataDir, fileName);
    
    % ---------------------------------------------------------------------
    % 2) 파일 존재 여부 확인 후 로드
    % ---------------------------------------------------------------------
    if ~exist(fullPath, 'file')
        warning('파일 %s 이(가) 존재하지 않습니다.', fullPath);
        continue;
    end
    
    loadedData = load(fullPath);
    if ~isfield(loadedData, 'Angle_sumout')
        warning('파일 %s 에 "Angle_sumout" 변수가 없습니다.', fullPath);
        continue;
    end
    
    angleData = loadedData.Angle_sumout;  % (N_pixel x N_scanline) 형태 가정

    % ---------------------------------------------------------------------
    % 3) 엔벨로프 검출 (Hilbert 변환)
    %    hilbert()는 열(column) 기준이므로, 전치(Transpose)에 유의
    % ---------------------------------------------------------------------
    envData = abs(hilbert(angleData.'));  % (N_scanline x N_pixel)
    envData = envData.';                  % 다시 (N_pixel x N_scanline)

    % ---------------------------------------------------------------------
    % 4) 로그 압축 (dB 스케일)
    %    20*log10(값/최댓값) → 최대값이 0 dB가 됨
    % ---------------------------------------------------------------------
    maxVal = max(envData(:));
    if maxVal == 0
        logEnvData = zeros(size(envData));
    else
        logEnvData = 20 * log10(envData / maxVal);
    end

    % ---------------------------------------------------------------------
    % 5) 플롯 (1행 numAngles열 서브플롯)
    % ---------------------------------------------------------------------
    subplot(1, numAngles, n);
    imagesc(logEnvData, [dB_min dB_max]);  % [dB_min, dB_max] 범위 지정
    colormap(cmap);
    colorbar;
    title(sprintf('Angle %02d (Frame %d)', n, frameNum));
    xlabel('Scanline');
    ylabel('Depth (pixel)');
end

% MATLAB 버전에 따라 전체 제목 표시
if exist('sgtitle', 'file')
    sgtitle('Beamformed Angle Sumout - Envelope & Log Compression (Single Row)');
else
    suptitle('Beamformed Angle Sumout - Envelope & Log Compression (Single Row)');
end

