function Bmode_compound_mid_backend()
% Bmode_compound_mid_backend.m
% -------------------------------------------------------------------------
% 5개 각도 컴파운딩(Front-end 빔포밍 결과)된 데이터를 불러와
% Mid Back-End 단계를 거쳐 최종 B-mode 영상을 생성하는 예시 코드.
%
% 1) 데이터 로드 (Compounding 결과)
% 2) DC 제거 (High-pass)
% 3) TGC (간단 예시)
% 4) Quadrature Demodulation (I/Q 신호)
% 5) Envelope Detection
% 6) Log Compression
% 7) Scan Conversion
% 8) B-mode 영상 디스플레이
% -------------------------------------------------------------------------

%% 0. 초기화 & 사용자 지정 파라미터
clc; close all; clearvars;

% ----------------- 파라미터(실제 환경에 맞게 수정) -----------------------
N_scanline    = 128;      % 스캔라인 개수
N_image_point = 1664;     % 깊이 방향 샘플 수
Fs            = 4 * 5.2083e6; % 샘플링 주파수 [Hz]
Fc            = 5.2083e6;     % 중심 주파수 [Hz]
c0            = 1540;         % 음속 [m/s] (인체 조직 기준)
Dynamic_Range = 60;           % dB 스케일 동적 범위
E_pitch       = 0.298e-3;     % 소자 간격 [m]
viewWidth     = (N_scanline - 1) * E_pitch * 1e3; % 횡방향(mm) 길이
Unit_distance = c0 / Fs;      % 샘플 하나당 거리 [m]
Depth_max     = N_image_point * Unit_distance;  % 최대 깊이 [m]

% (Scan Conversion 시) 최종 영상 해상도 설정
Num_pixel_z   = 1024;    % 깊이(세로) 방향 픽셀 수
Num_pixel_x   = 512;     % 횡방향(가로) 픽셀 수

% DC 제거용 FIR 고역 필터
HPF_order     = 32;
HPF_cutoff    = 0.1;     % (정규화 주파수, 1=Nyquist)

% Quadrature Demodulation용 LPF
LPF_order     = 48;
LPF_cutoff    = Fc / Fs; % 중심주파수 대비 저역통과
% -------------------------------------------------------------------------

%% 1. Compounding 결과 로드
% Compounding_Sumout_Data 폴더 내의 파일 예: "Compounding_sumout001frame.mat"
% 내부 변수: CAC_sumout (크기: [N_pixel x N_scanline] = [1664 x 128] 가정)
dataFile = 'Compounding_Sumout_Data\Compounding_sumout001frame.mat';
S = load(dataFile, 'CAC_sumout');
if ~isfield(S, 'CAC_sumout')
    error('파일에 CAC_sumout 변수가 없습니다: %s', dataFile);
end

% CAC_sumout: (Depth x Scanline) = (N_image_point x N_scanline)
% Mid Back-End 처리를 위해 (Scanline x Depth) 형태로 전치
Sum_out = S.CAC_sumout';  % 결과: [N_scanline x N_image_point]

disp('1) Compounding data loaded & transposed.');

%% 2. DC 제거(High-pass 필터)
DC_coef = fir1(HPF_order, HPF_cutoff, 'high');
DC_Cancel_out = convn(Sum_out, DC_coef, 'same');
disp('2) DC cancelation complete.');

%% 3. Time Gain Compensation (TGC)
% 여기서는 간단히 "깊이에 비례하여" 게인을 올리는 예시를 들어보겠습니다.
% 실제로는 실험에 맞는 TGC 곡선을 설계해야 합니다.

TGC_out = zeros(size(DC_Cancel_out));
depth_idx = (1:N_image_point).'; % 열(Depth) 기준
max_depth = N_image_point;       % 단순히 인덱스 기준
for sc = 1:N_scanline
    % 예: 선형으로 (1 ~ 2배) 증가
    % (실제는 dB 스케일로, 혹은 더 복잡한 곡선 사용 가능)
    gain_curve = 1 + (depth_idx / max_depth);  
    TGC_out(sc,:) = DC_Cancel_out(sc,:) .* gain_curve';
end

disp('3) TGC complete. (Simple linear ramp example)');

%% 4. Quadrature Demodulation
% 시간 인덱스
t_idx = 1 : N_image_point;
Cos_t = cos(2*pi * Fc/Fs * t_idx);
Sin_t = sin(2*pi * Fc/Fs * t_idx);

Data_I = zeros(size(TGC_out));
Data_Q = zeros(size(TGC_out));

% 각 스캔라인별로 복소신호(I/Q) 생성
for sc = 1:N_scanline
    Data_I(sc,:) = TGC_out(sc,:) .* Cos_t;
    Data_Q(sc,:) = TGC_out(sc,:) .* Sin_t;
end

% LPF 적용
LPF_coef  = fir1(LPF_order, LPF_cutoff, 'low');
Data_I_LPF = convn(Data_I, LPF_coef, 'same');
Data_Q_LPF = convn(Data_Q, LPF_coef, 'same');

disp('4) Quadrature Demodulation (I/Q + LPF) complete.');

%% 5. Envelope Detection
Envelope = sqrt(Data_I_LPF.^2 + Data_Q_LPF.^2);
disp('5) Envelope detection complete.');

%% 6. Log Compression
% dB 스케일로 변환
% 최대값 0 dB, 동적 범위=Dynamic_Range(dB)
Ymax = 256;  % 8-bit 스케일 가정
Xmax = max(Envelope(:));
Xmin = Xmax * 10^(-Dynamic_Range/20);

Log_out = zeros(size(Envelope));
mask = (Envelope >= Xmin);
Log_out(mask) = Ymax / log10(Xmax/Xmin) .* log10(Envelope(mask)/Xmin);

disp('6) Log compression complete.');

%% 7. Scan Conversion
% Log_out: [N_scanline x N_image_point]
% B-mode 디스플레이 위해 (Depth x Scanline)로 전치
bmode_in = Log_out';  % [N_image_point x N_scanline]

% 원본 좌표 설정
% Depth 축: 0 ~ Depth_max (m) → mm 단위
Axis_data_z = linspace(0, Depth_max*1e3, N_image_point);  % [mm]
Axis_data_x = linspace(-viewWidth/2, viewWidth/2, N_scanline);  % [mm]

% 최종 영상 해상도
Axis_image_z = linspace(0, Depth_max*1e3, Num_pixel_z);
Axis_image_x = linspace(-viewWidth/2, viewWidth/2, Num_pixel_x);

% 2D 보간
[X, Z]   = meshgrid(Axis_data_x, Axis_data_z);
[Xq, Zq] = meshgrid(Axis_image_x, Axis_image_z);

bmode_sc = interp2(X, Z, bmode_in, Xq, Zq, 'linear'); 
% 'cubic'으로 하면 더 부드럽지만 연산량이 증가

disp('7) Scan conversion complete.');

%% 8. B-mode 디스플레이
figure('Name','B-mode (Compound, Mid Back-End)','NumberTitle','off');
imagesc(Axis_image_x, Axis_image_z, bmode_sc);
colormap(gray); colorbar;
xlabel('Lateral [mm]');
ylabel('Depth [mm]');
title('B-mode Image (5-angle Compound)');

% caxis 자동 또는 백분위수로 설정
% 아래는 백분위수 2%~98%를 사용한 예
% x축 눈금을 -15부터 15까지 5 mm 간격으로 설정
xticks(-15 : 5 : 15);
xticklabels({'-15','-10','-5','0','5','10','15'});
caxis([0, 270]);

set(gca, 'YDir', 'reverse'); % 깊이가 아래 방향
axis image;                  % 픽셀 비율 1:1

disp('8) B-mode display complete.');

end
