%{ 
SCRIPT :: goTauchenMS.m 

This code should accomplish the following :
    
    1) Discretize each specification of MS-VAR
    2) Run Tests
    2) Simultate nSim discrete processes
    3) Simulate nSim continuous processes
    4) Compare means, median and confidence interval of estimates
   
TODO

    1) Test Asset Pricing capabilities

PARAMETERS

    nSim :: number of simulations of discrete & continuous DGP
    nTs :: length of each simulated series.
    N :: (K x Ns) matrix of nummber of discretized nodes for each
        dimension, and regime
    PhiCell :: (Ns x 1) cell of (K x K) autoregressive matrices
    muCell :: (Ns x 1) cell of (K x 1) intercept matrices
    CovCell :: (Ns x 1) cell of (K x K) covariance matrices
    Pi :: (Ns x Ns) transition matrix s.t. rows sum to unity
    m :: Number of std. dev. from mean to form grid
    
SPECIFICATIONS
    K = 2,3
    Ns = 2,4,8
    N = anisotropic grid, isotropic grid

%}
tic;
%% Global parameters
nSim = 500;
nTs = 1000;
m = 3;
llCell = cell(nSim,1);

for method = 1:1
   %% Set local parameters
   if method==1
        K = 2;
        Ns = 2;
        N = [5,10;5,10];
        PhiCell = cell(Ns,1);
        PhiCell{1} = [0.5, 0.1; 0, 0.7];
        PhiCell{2} = [0.85, 0; 0.1 , 0.2];
        muCell = cell(Ns,1);
        muCell{1} = [0.2; 0.1];
        muCell{2} = [0; 0];
        CovCell = cell(Ns,1);
        CovCell{1} = eye(K);
        CovCell{2} = [0.5, 0.2; 0.2, 0.8];
        Pi = [ 0.95, 0.05; 0.09, 0.91 ];
   else
       error('you''ve ran out of methods')
   end
   
   %Check for MSS
   MSS = chkMssMsvar(PhiCell,Pi);
   if MSS==0
       error('MSVAR not MSS')
   end
   
   %% Discretization
   prMatKeyCell = cell(Ns,1);
   prMatKeyPosCell = cell(Ns,1);
   prMatIntCell = cell(Ns,1);
   zBarCell = cell(Ns,1);

   % Get multivariate grids
   for jj=1:Ns
       [prMatKeyCell{jj},prMatKeyPosCell{jj},prMatIntCell{jj},zBarCell{jj}]...
           = getGrid(muCell{jj},PhiCell{jj},CovCell{jj},N(:,jj),m,1);
   end
   
   % Get Pi_{i,j}
   PiIJCell = cell(Ns,1);
   for ii=1:Ns
       for jj=1:Ns
           PiIJCell{ii,jj} = ...
               getPrMat(muCell{jj},PhiCell{jj},CovCell{jj},prMatIntCell{jj},...
                    prMatKeyCell{ii},size(prMatKeyCell{ii},2),...
                    size(prMatKeyCell{jj},2));
       end
   end
   
   % Mix Pi_{i,j}s to form dPi
   NNVec = NaN(Ns,1);  %Total number of discrete states between regimes
   for ii=1:Ns
       NNVec(ii) = size(prMatKeyCell{ii},2);
   end
   cumNN = cumsum(NNVec);
   NN = sum(NNVec);
   ndx = NaN(NN,1); %This vector indexes that state at each discrete state
   for ii=1:Ns
       if ii~=1
            ndx(1+cumNN(ii-1):cumNN(ii)) = ii;
       else
           ndx(1:cumNN(ii)) = ii;
       end
   end
   
   dPi = NaN(NN);
   cnt = 1;
   for ii=1:NN
       for jj=1:Ns
           if jj~=1
                dPi(ii,1+cumNN(jj-1):cumNN(jj)) = ...
                    Pi(ndx(ii),jj).*PiIJCell{ndx(ii),jj}(cnt,:);
           else
               dPi(ii,1:NNVec(jj)) = ...
                   Pi(ndx(ii),jj).*PiIJCell{ndx(ii),jj}(cnt,:);
           end
       end
       if ii~=NN
           if ndx(ii)==ndx(ii+1)
               cnt = cnt + 1;
           else
               cnt = 1;
           end
       end
   end
   
   %% Simulate nSim of each discrete & continuous series series
   dTsCell = cell(nSim,1);
   dSCell = cell(nSim,1);
   tsCell = cell(nSim,1);
   sCell = cell(nSim,1);
   u = [];
   for ii=1:Ns
      u = [u;prMatKeyCell{ii}']; 
   end
   
   %Discrete simulation
   for ii=1:nSim
        [dTsCell{ii},dSCell{ii}] = simMC(u,dPi,0,nTs,NN);
        disp(ii)
   end
   
   %Continuous simulation
   sigCell = cell(Ns,1);
   for ii=1:Ns
      sigCell{ii} = sqrtm(CovCell{ii});
   end
   qq = getStatMarkov(Pi);
   [tsCell,sCell{ii}] = ...
        simMSVarDL(muCell,PhiCell,sigCell,nTs,nSim,Pi,qq,0,u(tmp,:)');
     
   %Estimate via MLE
   init = [muCell{1};muCell{2};PhiCell{1}(:);PhiCell{2}(:);sqrt(diag(sigCell{1}));...
           sigCell{1}(2,1);sqrt(diag(sigCell{2}));sigCell{2}(2,1);diag(Pi)];
   lb = -inf * ones(20,1);
   ub = inf*ones(20,1);
   lb(end-1:end) = eps*ones(2,1);
   ub(end-1:end) = ones(2,1);
   lb(13:18) = zeros(6,1);
   A = zeros(20);
   A(1,18) = 1;
   A(1,17) = -1;
   A(1,16) = -1;
   A(2,15) = 1;
   A(2,14) = -1;
   A(2,13) = -1;
   options = optimoptions(@fmincon,'Display','iter');
   dEstCell = cell(nSim,1);
   dLlMat = NaN(nSim,1);
   estCell = cell(nSim,1);
   llMat = NaN(nSim,1);
   parpool(32)
   par for ii=1:nSim
        [dEstCell{ii}, dLlMat(ii)] = ...
            fmincon(@(X) nLogLik_1(dTsCell{ii},X,1,2,2),init,A,b,[],[],lb,ub,...
                [],options);
        [estCell{ii}, llMat(ii)] = ...
            fmincon(@(X) nLogLik_1(tsCell{ii},X,1,2,2),init,A,b,[],[],lb,ub,...
                [],options);
   end
   
   
   resMat = NaN(20,4); %Mean, median, 2.5 prctle, 97.5 prctle
   dResMat = NaN(20,4);
   resMat = [mean(cell2mat(estCell'),2),prctle(cell2mat(estCell'),50,2),...
             prctle(cell2mat(estCell'),2.5,2),...
             prctle(cell2mat(estCell'),95,2)];
   dResMat = [mean(cell2mat(dEstCell'),2),prctle(cell2mat(dEstCell'),50,2),...
             prctle(cell2mat(dEstCell'),2.5,2),...
             prctle(cell2mat(dEstCell'),95,2)];
         
    mseVec = NaN(2,2);
    mseVec(1,1) = ((mean(cell2mat(dEstCell'),2)-init).^2)./(nSim-1);
    mseVec(2,1) = ((prctile(cell2mat(dEstCell'),50,2)-init).^2)./(nSim-1);
    mseVec(1,2) = ((mean(cell2mat(estCell'),2)-init).^2)./(nSim-1);
    mseVec(2,2) = ((prctile(cell2mat(estCell'),50,2)-init).^2)./(nSim-1);
   
   
   %Asset pricing
   a = 0.9; %arbitrary
   b = 0.2;
   %c = 0; 
   te = [a,b];
   d = 0;
   eta = NaN(NN,1);
   cnt=1;
   for mm=1:M
       for ii=1:NNVec(mm)
           eta(cnt) = te*prMatKeyCell{mm}(:,ii) + d;
           cnt = cnt + 1;
       end
   end
   
   sp = (eye(nn)-eta.*dPi)\eta;
       
   save('results.mat');
       
   
    
 
end