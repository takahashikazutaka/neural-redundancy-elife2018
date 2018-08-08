function [Z, mu] = bestMeanFit(Tr, Te, dec, opts)
    if nargin < 4
        opts = struct();
    end
    defopts = struct('grpName', 'thetaActualGrps', 'addNoise', true, ...
        'nReps', 10, 'obeyBounds', true, 'nanIfOutOfBounds', false);
    opts = tools.setDefaultOptsWhenNecessary(opts, defopts);

    Z1 = Tr.latents;
    Z2 = Te.latents;
    NB2 = Te.NB;
    RB2 = Te.RB;
    nt = size(Z2,1);

    % find best mean; predict this mean as constant in NB
    mu = findBestNullSpaceMean(Z1, NB2, Te.M0, Te.M2);
    Zn = repmat(mu, nt, 1)*NB2';
    Zr = Z2*(RB2*RB2');
    Z = Zr + Zn; Z0 = Z;
    
    % add noise
    if opts.addNoise
        sps0 = tools.latentsToSpikes(Z, dec, false, true);
        sps = poissrnd(max(sps0,0));
        Z = tools.convertRawSpikesToRawLatents(dec, sps');
    end
    
    % correct to be within bounds if noise was added
    if opts.obeyBounds && opts.addNoise
        isOutOfBounds = tools.boundsFcn(Tr.spikes, 'spikes', dec, true);
        ixOob = isOutOfBounds(sps); % might be fixed by resampling noise
        n0 = sum(ixOob);
        c = 0;
        while sum(ixOob) > 0 && c < opts.nReps
            sps(ixOob,:) = poissrnd(max(sps0(ixOob,:),0));
            ixOob = isOutOfBounds(sps);
            c = c + 1;
        end
        Z = tools.convertRawSpikesToRawLatents(dec, sps');
        if n0 - sum(ixOob) > 0
            disp(['Corrected ' num2str(n0 - sum(ixOob)) ...
                ' best-mean sample(s) to lie within bounds']);
        end
    end
        
    if opts.obeyBounds && opts.nanIfOutOfBounds
        isOutOfBounds = tools.boundsFcn(Tr.spikes, 'spikes', dec, false);
        ixOob = isOutOfBounds(Z);
        Z(ixOob,:) = nan;
    end
    
    Z = Z*(NB2*NB2') + Zr; % maintain same output-potent value
end

function muh = findBestNullSpaceMean(Z, NB, M0, M2)
    % figure out which direction bin Z would move the cursor
    %   with the current decoder
    vsf = @(Y) bsxfun(@plus, Y*M2', M0');
    gsf = @(Y) tools.computeAngles(vsf(Y));
    gs = tools.thetaGroup(gsf(Z), tools.thetaCenters);
    
    % objective now for prediction muh is [with mu := grpstats(Z*NB, gs)]
    %   sum_i || muh - mu(ii,:) ||^2
    % = sum_i 0.5*muh'*muh - muh'*mu(ii,:) + const
    % = (nd/2)*muh'*muh - sum_i muh'*mu(ii,:)
    % = (nd/2)*muh'*muh - muh'*sum(mu);
    % [d/d_muh = 0] -> nd*muh - sum(mu) = 0 -> muh = mean(mu)
    muh = mean(grpstats(Z*NB, gs)); % minimizes error in mean
end
