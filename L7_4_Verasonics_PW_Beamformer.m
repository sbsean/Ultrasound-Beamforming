clc; clear all; close all;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Data load .mat file (Verasonics Inc.)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
load('RcvData\Verasonics_parameters');

RcvData = cell2mat(RcvData);
RcvData = double(RcvData);
[Rcv_row, Rcv_col, Rcv_frame] = size(RcvData);

disp('"Verasonics" RcvData load');
disp('Data parameter load');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Planewave parameter
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
N_angle = na;
N_frame = 1;

dtheta = (degree*pi/180) / (N_angle-1);

start_degree = degree/2;
angle_step = degree / (N_angle-1);

steer_degree = zeros(1, N_angle);
for n = 1:N_angle
    steer_degree(n) = (-start_degree + angle_step*(n-1)) * pi/180;
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Data acquisition parameter (Verasonics Inc.)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
C = Resource.Parameters.speedOfSound;       % Speed of sound [m/s]
F0 = 5.2083e6;                              % Transducer Center frequency [Hz] 
Fs = 4 * F0;                                % Sampling frequency [Hz]
Lambda = C / F0;                            % Wavelength [m]
E_pitch = 0.2980e-3;                        % Element pitch [m]
Rx_element = 128;
N_element = 128;
Tx_element = 128;
Unit_distance = C / Fs;                     % 기본 단위 길이 [m]
Inter_coeff = 4;
N_pixel = 1664;
N_scanline = 128;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Tx offset for steering delay
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
Tx_offset_angle = zeros(1, N_angle);
for angle = 1:N_angle
    Tx_delay = TX(angle).Delay;
    Tx_offset_angle(angle) = ceil(Tx_delay(Rx_element/2) - min(Tx_delay));
end
Tx_offset_angle = Tx_offset_angle * Lambda;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Lens correction & Pulse wave peak correction
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
Lens_corr = Trans.lensCorrection;   % Lens correction
Lens_corr = Lens_corr * Lambda;
Tx_lens_corr = Lens_corr;
Rx_lens_corr = Lens_corr;
% Tx_lens_corr = 0;
% Rx_lens_corr = 0;

PW_peak = TW.peak * Lambda;  % Peak wave correction for transmit pulse

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Channel data generation
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
RF_data_temp = zeros(N_pixel, Rx_element, N_angle, N_frame);
for frame = 1:N_frame
    for n = 1:N_angle
       RF_data_temp(:, :, n, frame) = RcvData((n-1)*N_pixel+1 : n*N_pixel, :, frame);
    end
end

disp('Channel data generation');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Interpolation filter
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
if (Inter_coeff ~= 1)
    N     = 32;                      % Filter order
    Fpass = 1/Inter_coeff * 0.8;      % Passband Frequency
    Fstop = 1/Inter_coeff * 1.2;      % Stopband Frequency
    Wpass = 1;                        % Passband Weight
    Wstop = 1;                        % Stopband Weight
    Int_filter = fir1(N, 1/Inter_coeff, 'low');
else
    Int_filter = 1;
end
disp('Interpolation Filter Generation');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Delay calculator
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
Address = zeros(Rx_element, N_pixel*Inter_coeff, N_scanline, N_angle);
Inter_pixel = 1:N_pixel*Inter_coeff;  % Inter_pixel = k

disp('Beamforming complete');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Compound image display (그레이스케일, 물리 좌표: mm)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% compound 이미지 데이터 파일 불러오기
load('Compounding_Sumout_Data\Compounding_sumout001frame.mat');

% (이미지 데이터 변수는 기본적으로 CAC_sumout으로 가정; 크기: [N_pixel x N_scanline])

% 좌표 계산
y_mm = (0:N_pixel-1) * (Unit_distance * 1000);  % Depth (mm)
viewWidth = (N_scanline - 1) * E_pitch * 1000;    % 전체 Width (mm)
x_mm = linspace(-viewWidth/2, viewWidth/2, N_scanline);  % Width (mm)

% Compound 이미지 출력
figure;
imagesc(x_mm, y_mm, CAC_sumout);  % 그레이스케일 이미지
axis image;
colormap(gray);
colorbar;
xlabel('View width (mm)', 'FontSize', 12, 'Color', [0.5 0 0.5]);  % 보라색 계열
ylabel('View depth (mm)', 'FontSize', 12, 'Color', [0 0.5 0]);      % 녹색 계열
title('Compound Image (CAC\_sumout)', 'FontSize', 14, 'FontWeight', 'bold');

% ★ 수정: 위에서 아래로 촬영하는 관점에 따라 y축 상단에 Depth 0이 위치하도록 설정
set(gca, 'YDir', 'reverse');

% x축은 5mm 단위, y축은 10mm 단위로 눈금 설정
xticks(-viewWidth/2 : 5 : viewWidth/2);
yticks(0 : 10 : max(y_mm));

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% B-mode image generation (Mid back-end; 리니어 포커스드 참조 코드 구조 반영)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 포락선 검출: Hilbert 변환을 이용하여 envelope 계산
env_img = abs(hilbert(CAC_sumout));

% 로그 압축
log_img = 20 * log10(env_img + eps);

% 정규화 (0~1 사이)
norm_img = (log_img - min(log_img(:))) / (max(log_img(:)) - min(log_img(:)));

% 8-bit 이미지 변환
bmode_img = uint8(norm_img * 255);

% B-mode 이미지 출력
figure;
imagesc(x_mm, y_mm, bmode_img);
colormap(gray);
axis image;
colorbar;
caxis([0, 300]);
xlabel('View width (mm)', 'FontSize', 12, 'Color', [0.5 0 0.5]);
ylabel('View depth (mm)', 'FontSize', 12, 'Color', [0 0.5 0]);
title('B-mode Image', 'FontSize', 14, 'FontWeight', 'bold');

% ★ 수정: 위와 동일하게 y축 상단에 Depth 0이 위치하도록 설정
set(gca, 'YDir', 'reverse');

% x축은 5mm 단위, y축은 10mm 단위로 눈금 설정
xticks(-viewWidth/2 : 5 : viewWidth/2);
yticks(0 : 10 : max(y_mm));




 