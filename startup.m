% startup.m
% MATLAB 시작 시 자동 실행되어 기본 figure 창을 설정합니다.

% figure 단위를 픽셀로 설정합니다.
set(0, 'DefaultFigureUnits', 'pixels');

% figure 위치 및 크기를 설정합니다.
% 배열의 순서는 [left, bottom, width, height]이며,
% 여기서 width(가로)가 600 픽셀, height(세로)가 800 픽셀로 설정되어 있습니다.
set(0, 'DefaultFigurePosition', [100, 100, 600, 800]);

disp('Default figure window set: width 600px, height 800px (가로가 세로보다 짧은 형태)');
