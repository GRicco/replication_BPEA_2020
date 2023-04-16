function Res = QRboot(X, y, H, includeLagY, QQ, nDrawsBoot, nLagsBootVAR)
%% QRboot: quantile regression with optional bootstrapped confidence bands.
% 
% Description: QRboot carries out the quantile regression of (averaged 
% values of) y on X for the requested forecasting horizons and quantiles.
% More specifically, for a given forecasting horizon h > 0:
%   - The dependent variable in the quantile regressions is given by
%     yh(t+h) = (y(t+1) + ... + y(t+h)) / h, the average value of y over
%     the periods t+1,...,t+h
%   - The conditioning variables are given by X(t,:); optionally, the
%     current value of y can be included as conditioning variables if
%     specified in the optional arguments.
% The quantile regressions are estimated for all of the quantiles listed in
% QQ.
%
% Optionally, a bootstrap sample for the quantile regression coefficients
% will be generated by fitting a vector autoregression (VAR) for the
% variables in both y and X, generating samples of equal length to the
% original sample by using the estimated VAR parameters, and re-estimating
% each quantile regression using the generated sample.
% 
% Input arguments:
% - X : Matrix containing the conditioning variables. A column of ones will
%       automatically be added to X, so that an intercept term is always
%       included in regressions. If an empty matrix is provided, the
%       unconditional quantiles of y will be computed. NOTE: lags of the
%       dependent variable should not be included in X; rather, this should
%       be specified using the includeLagY argument.
% - y : Vector containing the variable to be forecasted, with length equal
%       to the number of rows in X. For a given forecasting horizon h > 0,
%       the value of the dependent variable at time t in each regression is
%       the average value of y over the next h periods.
% - H : Vector of positive integers indicating the forecasting horizons at
%       which the quantile regressions will be estimated.
% - includeLagY : Integer; if == 1 then the current value of y will be
%                 included in the quantile regressions. Defaults to 0 
%                 (current value of y not included in quantile regression).
% - QQ : Vector of numbers between 0 and 1 indicating all of the quantiles
%        for which the quantile regression should be estimated. Defaults to
%        0.05:0.05:0.95
% - nDrawsBoot : Number of bootstrapped samples to generate. If not
%                specified or if set == 0, bootstrapping procedure will be
%                skipped. Defaults to 0.
% - nlagsBootVAR : Number of lags to include in the VAR fit to y and X that
%                  will be used to generate bootstrapped samples. Defaults 
%                  to 4.
%
% Output arguments:
% - Res : struct containing the following fields (for convenience let T
%         denote the number of rows of X and let k denote the number of
%         conditioning variables included in each regression, including the
%         intercept and lagged dependent variable values)
%   - BQ : Array with dimensions (k, length(QQ), max(H)) such that
%          BQ(:, jq, h) contains the estimated quantile regression
%          coefficients for the jqth quantile and forecasting horizon h.
%   - YQ : Array with dimensions (T, length(QQ), max(H)) such that
%          YQ(t, jq, h) contains the fitted conditional jqth quantile for
%          y(t).
%   - B2 : Array with dimensions (k, max(H)) such that B2(:, h) contains
%          the estimated OLS coefficients for forecasting horizon h.
%   - Y2 : Array with dimensions (k, max(H)) such that Y2(t, h) contains
%          the OLS fitted value for y(t).
%   - bBQ : If nDrawsBoot > 0, array with dimensions
%           (k, length(QQ), max(H), nDrawsBoot) such that bBQ(:, jq, h, n)
%           contains the estimated quantile regression coefficients for the
%           jqth quantile and forecasting horizon h, estimated from the nth
%           bootstrapped sample.
%   - bB2 : If nDrawsBoot > 0, array with dimensions
%           (T, max(H), nDrawsBoot) such that bBQ(t, h, n) contains the
%           estimated OLS coefficients for forecasting horizon h, estimated
%           from the nth bootstrapped sample.
%
% NOTE: if the integers in H are not consecutive, then the entries in Res
% corresponding to the forecasting horizons not included in h will be
% filled with zeros, i.e. if H = [1,4] then Res.BQ(:,:,2:3) will consist of
% zeros.
%% Set values for missing arguments
if ~exist('includeLagY', 'var')
    includeLagY = 0;
end

if ~exist('QQ', 'var')
    QQ = .05:.05:.95;
end

if ~exist('nDrawsBoot', 'var')
    nDrawsBoot = 0;
end

if ~exist('nLagsBootVAR', 'var')
    nLagsBootVAR = 4;
end

% Store quantile indicators in output structure.
Res.QQ = QQ;

%% Organize data
% Create matrix Z containing column of ones, variables in X, and (possibly)
% the contemporaneous value of y.
Z = [ones(size(y)), X];
if includeLagY
    Z = [Z, y];
end

% Create matrix Yh where Yh(t+h,h) = (y(t+1) + ... + y(t+h)) / h,
% i.e. Yh(t+h,h) is the average value of y from t+1 to t+h.
for h = H
    Yh(:, h) = filter(ones(1, h) / h, 1, y);
    Yh(1:(h - 1), h) = NaN;
end

%% Quantile (and OLS) regression for each forecasting horizon/quantile pair
for h = H
    yh = Yh((h + 1):end, h);
    Zh = Z(1:(end - h), :);
    % OLS regression of yh on Zh
    b2 = Zh \ yh;
    B2(:, h) = b2;
    Y2(:, h) = [NaN(h, 1); Zh * b2]; % store fitted values
    for jq = 1:length(QQ)
        % Quantile regression of yh on Zh (for the jqth quantile)
        bq = rq(Zh, yh, QQ(jq));
        BQ(:, jq, h) = bq';
        YQ(:, jq, h) = [NaN(h, 1); Zh * bq]; % store fitted quantiles
    end
end

Res.YQ = YQ;
Res.BQ = BQ;
Res.Y2 = Y2;
Res.B2 = B2;

%% Generate bootstrapped samples to reestimate coefficients

% Generate bootstrapped samples by fitting VAR to data
DataBoot = VARsimul([y, X], nLagsBootVAR, nDrawsBoot);
DataBoot = DataBoot(1:length(y), :, :);

% Reestimate coefficients for each generated sample
for jm = 1:nDrawsBoot
    if mod(jm, 50) == 0
        disp(['Now running the ', num2str(jm), 'th iteration'])
    end
    
    % Construct matrix Yh containing h-period averages of y
    y = DataBoot(:, 1, jm);
    for h = H
        Yh(:, h) = filter(ones(1, h) / h, 1, y);
        Yh(1:(h - 1), h) = NaN;
    end
    
    % Construct matrix Z of conditioning variables.
    Z = [ones(size(y)) DataBoot(:,2:end,jm)];
    if includeLagY
        Z = [Z, y];
    end
    
    % Reestimate coefficients for each horizon/quantile pair
    for h = H
        yh = Yh((h + 1):end, h);
        Zh = Z(1:(end - h), :);
        % OLS regression of yh on Zh
        b2 = Zh \ yh;
        bB2(:, h, jm) = b2;
        for jq = 1:length(QQ)
            % Quantile regression of yh on Zh (for the jqth quantile)
            bq = rq(Zh, yh, QQ(jq));
            bBQ(:, jq, h, jm) = bq'; % store coefficients
        end
    end
end

if nDrawsBoot > 0
    Res.bBQ = bBQ;
    Res.bB2 = bB2;
end

function XXb = VARsimul(X, p, nSim)
%% VARsimul: fit VAR to data and generate samples of equal length
%
% Description: VARsimul fits a VAR with p lags to the provided data X and
% uses the estimated parameters to simulate samples of equal length (using
% the same p initial values contained in X and Gaussian shocks with
% covariance matrix estimated from the data).
% 
% Input arguments:
% - X : T-by-N matrix containing data used to estimate the VAR parameters.
% - p : Number of lags to include in the estimated VAR.
% - nSim : Number of samples to generate using the estimated parameters.
%
% Output arguments:
% - XXb : T-by-N-by-nSim array, such that XXb(:,:,m) contains a simulated
%         sample.

%% Estimate VAR parameters using data provided in X
[T, N] = size(X);
% Construct Z matrix of right-hand side variables (constant plus lags of X)
Z = ones(T - p, 1);
for j = 1:p
    Z = [Z, X((p + 1 - j):(T - j), :)];
end
y = X((p + 1):end, :);
% Estimate VAR coefficient matrix and innovation covariance matrix
beta = Z \ y;
Sigma = cov(y - Z * beta);

%% Simulate samples
XXb = zeros(T, N, nSim); % array to store simulated samples
for m = 1:nSim
    clear('Xb')
    Xb(1:p, :) = X(1:p, :); % use the p initial values from the data X
    err = randn(T, N) * chol(Sigma); % draw errors
    for t = (p + 1):T
        % Construct Zt matrix of time t values for conditioning variables
        Zt = 1;
        for j = 1:p
            Zt = [Zt, Xb(t - j, :)];
        end
        Xb(t, :) = Zt * beta + err(t, :);
    end
    XXb(:, :, m) = Xb;
end