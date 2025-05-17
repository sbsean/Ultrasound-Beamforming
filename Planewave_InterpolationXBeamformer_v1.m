clc; clear all; close all;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 1) 데이터(.mat) 로드
% 2) 파라미터 설정
% 3) Tx offset 계산
% 4) 채널 데이터 구성
% 5) 인터폴레이션 필터 생성
% 6) 지연(Delay) 테이블 계산
% 7) Aperture Growth & Apodization
% 8) 빔포밍(Beamforming) 수행
%
% 5개 각도(Compounding) 고정.
% 노이즈 완화를 위해 Apodization_window 덮어씌우던 부분 제거.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% 1. Load Verasonics RcvData
load('RcvData\Verasonics_parameters.mat');  % RcvData(cell)에 저장
RcvData = cell2mat(RcvData);                % cell → matrix
RcvData = double(RcvData);
[Rcv_row, Rcv_col, Rcv_frame] = size(RcvData);

disp('"Verasonics" RcvData loaded.');

%% 2. Planewave Compounding Parameter
N_angle   = 5;       % 총 각도 수(5개)
degree    = 20;      % 총 스팬(deg) → -10°, -5°, 0°, +5°, +10°
N_frame   = 1;       % 사용할 프레임 수 (예: 1)

% 각도(step) 계산
dtheta       = (degree * pi/180) / (N_angle - 1);
start_degree =  degree/2;
angle_step   =  degree / (N_angle - 1);
steer_degree = zeros(1, N_angle);

for n = 1:N_angle
    steer_degree(n) = (-start_degree + angle_step*(n-1)) * pi/180;
end

%% 3. Data Acquisition Parameter
C          = 1450;         % Speed of sound [m/s] (물속 실험이었는지 확인 필요)
F0         = 5.2083e6;     % Transducer Center frequency [Hz]
Fs         = 4 * F0;       % Sampling frequency [Hz]
Lambda     = C / F0;       % 파장
E_pitch    = 298e-6;       % 소자 간격 [m]
N_element  = 128;          % 전체 소자 수
Rx_element = 128;          % Rx 소자 수
N_scanline = 128;          % 스캔라인 수
View_width = E_pitch * N_element;  % 횡방향(가로) 폭
Depth      = 70e-3;        % 심도 [m]
N_pixel    = Rcv_row / N_angle;  % 각도별 샘플 수
Unit_distance = C / Fs;    % 샘플 당 거리
Inter_coeff   = 4;         % 인터폴레이션 계수
F_number      = 1.0;       % F-number
Tx_offset     = 50;        % 추가 오프셋(사용자 정의)

disp('Basic parameters set.');

%% 4. Tx offset generation
% X_ch : 각 소자의 x좌표(단위: 샘플 거리)
X_ch = (0:Rx_element-1) * E_pitch + 0.5 * E_pitch;  
X_ch_center = (Rx_element / 2) * E_pitch;          
X_ch = (X_ch - X_ch_center) / Unit_distance;  

Tx_offset_angle = zeros(1, N_angle);
for angle = 1:N_angle
    Xincr = sin(steer_degree(angle));
    Yincr = cos(steer_degree(angle));
    % 매우 큰 거리(1e10/2)에서의 지연 차이 계산 (과거 코드 방식)
    Tx_delay = round( sqrt( (X_ch + 1e10/2 * Xincr).^2 + (1e10/2 * Yincr)^2 ) );
    Tx_offset_angle(angle) = Tx_delay(Rx_element/2) - min(Tx_delay);
end

disp('Tx offset generation complete.');

%% 5. Channel Data Generation (분할)
% RcvData : [N_pixel * N_angle, Rx_element, N_frame]
% → angle별로 잘라서 RF_data_temp(:,:,(angle), frame)에 저장
RF_data_temp = zeros(N_pixel, Rx_element, N_angle, N_frame);
for frame = 1:N_frame
    for n = 1:N_angle
        idx_start = (n-1)*N_pixel + 1;
        idx_end   = n * N_pixel;
        RF_data_temp(:,:,n,frame) = RcvData(idx_start:idx_end, :, frame);
    end
end

disp('Channel data generation complete.');

%% 6. Interpolation Filter Generation
if (Inter_coeff ~= 1)
    N       = 32;          % Filter order
    Fpass   = 1/Inter_coeff * 0.8;  % Passband
    Fstop   = 1/Inter_coeff * 1.2;  % Stopband
    Wpass   = 1;           % Passband Weight
    Wstop   = 1;           % Stopband Weight
    Int_filter = fir1(N, 1/Inter_coeff, 'low');
else
    Int_filter = 1;
end

disp('Interpolation filter generated.');

%% 7. Delay Calculator
Address = zeros(Rx_element, N_pixel*Inter_coeff, N_scanline, N_angle);
Inter_pixel = 1 : (N_pixel*Inter_coeff);

% Aperture 좌표
positive_x = 0:(Rx_element/2 - 1); % 0~63
Element_positive_x = positive_x * E_pitch + E_pitch/2;
negative_x = -(Rx_element/2 - 1):1:0; % -63~0
Element_negative_x = negative_x * E_pitch - E_pitch/2;
Element_x = [Element_negative_x, Element_positive_x];
Element_z = zeros(1, Rx_element);

% Scanline x좌표
Scan_positive_x = 1:(Rx_element/2 - 1);
Scan_negative_x = -(Rx_element/2):1:-1;
Scan_pos = [Scan_negative_x, 0, Scan_positive_x] * E_pitch;  % -32*pitch ~ 0 ~ 32*pitch

% z방향 증가량
Incr_z = Unit_distance;
Scan_z = 0;  % 스캔라인 z 시작점

% 이미지 좌표
Img_x = 0 + 0 * (Inter_pixel/2);   % 실제론 0
Img_z = Scan_z + (Incr_z * Inter_pixel / 2);

% Delay 계산
for n = 1:N_angle
    for sc = 1:N_scanline
        for z = 1:(N_pixel * Inter_coeff)
            for x = 1:Rx_element
                % 전방향/후방향 경로 지연 계산
                Address(x,z,sc,n) = floor( ...
                    ( sqrt(Img_x(z)^2 + Img_z(z)^2) * cos(steer_degree(n)) ...
                    + Scan_pos(sc)*sin(steer_degree(n)) ...
                    + sqrt( (Img_x(z)-Element_x(x))^2 + (Img_z(z)-Element_z(x))^2 ) ) ...
                    * Fs / C * Inter_coeff );
            end
        end
        disp(sprintf('Addr calc: angle %d / scanline %d done.', n, sc));
    end
end

% Address 범위 제한
index = find(Address > N_pixel*Inter_coeff);
Address(index) = N_pixel*Inter_coeff;
ind = find(Address < 1);
Address(ind) = 1;

disp('Time Delay Calculation complete.');

%% 8. Aperture Growth & Apodization
Active_aper_num = zeros(1, N_pixel);

% (a) Aperture 성장
for depth_point = 1:N_pixel
    Active_aper_num(depth_point) = floor( ...
        ((depth_point * (Unit_distance/2)) / E_pitch) * F_number );
    idx_exceed = find(Active_aper_num > Rx_element);
    Active_aper_num(idx_exceed) = Rx_element;
end

% (b) 유효 Aperture(Effective_aperture) 계산
Effective_aperture_half = ones(Rx_element/2, N_pixel);
for depth_point = 1:N_pixel
    for h = 1:(Rx_element/2)
        if Active_aper_num(depth_point) < h
            Effective_aperture_half(h, depth_point) = 0;
        end
    end
end
% 좌우 대칭
Effective_aperture = [flipud(Effective_aperture_half)', Effective_aperture_half']';

% (c) Apodization windowing
Apodization_window = zeros(Rx_element, N_pixel);
for depth_point = 1:N_pixel
    % 유효 aperture 크기만큼 hann 윈도우 적용
    active_count = sum(Effective_aperture(:, depth_point));
    apod_coef = kaiser(active_count, 4)';  % 1 x active_count
    zero_pad = zeros(1, (Rx_element - active_count)/2);
    apodization_coef_R = [zero_pad, apod_coef, zero_pad];
    Apodization_window(:, depth_point) = apodization_coef_R;
end

% 기존 코드에서는 다음 줄로 인해 모든 Apodization이 1이 되어버림
%   Apodization_window = ones(N_scanline, N_pixel);
% 이 부분이 실제로 Apodization을 무효화하여 노이즈가 커지는 원인이 됨.
% --> **제거**하여 실제 hann 가중이 적용되도록 함.

disp('Aperture growth & Apodization complete.');

%% 9. Beamforming Generation
% 결과 저장 폴더 생성
mkdir('Angle_Sumout_Data');
mkdir('Compounding_Sumout_Data');

Angle_sumout = zeros(N_pixel, N_scanline);
CAC_sumout   = zeros(N_pixel, N_scanline);

% (출력 변수 미사용 - Sum_out)
Sum_out = zeros(N_scanline, N_pixel, N_angle);

% 메모리 할당
RF_data_upsample = zeros(1, N_pixel * Inter_coeff);
RF_data_int      = zeros(Rx_element, N_pixel * Inter_coeff);
RF_data          = zeros(N_pixel, N_scanline);

for frame = 1:N_frame
    for n = 1:N_angle
        % (a) Rx_element*2 크기의 임시 버퍼
        RF_data_ch = zeros(N_pixel, Rx_element*2);

        % 64칸 오른쪽으로 채널 데이터 배치
        for k = 1:N_scanline
            RF_data_ch(:, 64+k) = RF_data_temp(:, k, n, frame)';
        end

        % (b) 스캔라인별 빔포밍
        for sc = 1:N_scanline
            % 1) Tx offset 보정
            RF_tmp      = zeros(N_pixel, Rx_element);
            RF_data_tmp = zeros(N_pixel, Rx_element);

            for k = 1:N_scanline
                RF_data_tmp(:, k) = RF_data_ch(:, (k-1) + sc);
            end

            idx_start = Tx_offset_angle(n) + Tx_offset;
            if (idx_start < 1), idx_start = 1; end
            if (idx_start > N_pixel), idx_start = N_pixel; end

            len_valid = N_pixel - (Tx_offset_angle(n) + Tx_offset) + 1;
            if len_valid < 1, len_valid = 1; end
            if len_valid > N_pixel, len_valid = N_pixel; end

            % 유효 구간만 옮겨서 RF_tmp에 저장
            RF_tmp(1:len_valid, :) = RF_data_tmp(idx_start : idx_start+len_valid-1, :);
            RF_data = RF_tmp';  % [Rx_element x N_pixel]

            % 2) 인터폴레이션
            for h = 1:Rx_element
                RF_data_upsample = upsample(RF_data(h,:), Inter_coeff);
                RF_data_int(h,:) = convn(RF_data_upsample, Int_filter, 'same');
            end

            % 3) Delay 기반으로 샘플 추출 + Apodization 적용
            Data_aligned = zeros(Rx_element, N_pixel);
            for z = 1:N_pixel
                for x = 1:Rx_element
                    idx_delay = Address(x, z, sc, n);
                    Data_aligned(x, z) = RF_data_int(x, idx_delay) ...
                        * Apodization_window(x, z);
                end
            end

            % 4) Summation (각 소자 합)
            Data_aligned = Data_aligned';  % [N_pixel x Rx_element]
            Angle_sumout(:, sc) = sum(Data_aligned, 2);

            disp(sprintf('Beamforming: frame=%d / angle=%d / scanline=%d done.', ...
                         frame, n, sc));
        end

        % (c) 각도별 sumout 저장
        pathA = 'Angle_Sumout_Data\Angle_';
        fnameA = sprintf('sumout%02ddegree_%03dframe', n, frame);
        save([pathA fnameA], 'Angle_sumout');

        % (d) Compounding 합산
        CAC_sumout = CAC_sumout + Angle_sumout;
    end

    % (e) Compounding 결과 저장
    pathC = 'Compounding_Sumout_Data\Compounding_';
    fnameC = sprintf('sumout%03dframe', frame);
    save([pathC fnameC], 'CAC_sumout');
end

disp('Beamforming & Compounding complete.');


















 