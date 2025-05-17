% MAT 파일 불러오기
load('Compounding_Sumout_Data\\Compounding_sumout001frame.mat'); 

% 파일 내 변수 확인 (옵션)
whos

% compound 이미지 출력 (변수명이 'compound'인 경우)
figure;
imshow(compound, []);   % []는 이미지의 최소/최대 값을 자동 스케일링해줍니다.
colormap(gray);         % 그레이스케일 컬러맵 적용
