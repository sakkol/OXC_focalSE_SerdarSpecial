%% ========================================================================
%  OXC IN FOCAL STATUS EPILEPTICUS — Analysis Pipeline
%  Retrospective Single-Center Case Series
%  Efficacy & Tolerability of Oxcarbazepine in Focal SE
%  -----------------------------------------------------------------------
%    • Four key figures:
%        Fig 1: Length of Stay — Hospital + ICU LOS combined in one figure
%        Fig 2: OXC Loading Dose (mg/kg) — median line colour changed to black
%        Fig 3: Sodium Trajectory — Na=135 label removed; Na=145 line added
%        Fig 4: Efficacy Summary — seizure cessation, first dose response,
%                and further escalation combined into one 100%-stacked figure
%    • Analyses section: six pre-specified association tests only
%        1. Seizure type × responder class (chi-square)
%        2. Hospital LOS × responder class (Kruskal-Wallis)
%        3. ICU LOS × responder class (Kruskal-Wallis)
%        4. Loading dose mg/kg × hyponatremia Yes/No (Wilcoxon rank-sum)
%        5. Etiology category × responder class (chi-square)
%        6. First dose response × responder class (chi-square)
%        7. Setting of SE onset x responder class
%  -----------------------------------------------------------------------
%  HOW TO RUN:
%    1. Place this file and OXC_FocalSE_Data.xlsx together.
%    2. Open MATLAB (R2023a + Statistics & Machine Learning Toolbox).
%    3. Run the script (F5).  Figures → FIGDIR path below.
%  -----------------------------------------------------------------------
%  Statistical approach:
%    Descriptive: median (IQR, range) for continuous; n (%) for categorical.
%    Associations: Kruskal-Wallis or Wilcoxon rank-sum for continuous vs
%    categorical; chi-square or Fisher's exact for categorical vs categorical.
%    No multiplicity correction; all tests hypothesis-generating.
%% ========================================================================

clear; clc; close all;

%% ── 0. SETUP ─────────────────────────────────────────────────────────────

FILE   = "OXC_FocalSE_Data.xlsx";
SHEET  = 'Patient Data';
FIGDIR = 'Figures';

if ~exist(FIGDIR,'dir'), mkdir(FIGDIR); end

% Colour palette (ColorBrewer-inspired, 8 levels)
PALETTE = [ ...
    0.122 0.471 0.706; ...   % blue
    0.200 0.627 0.173; ...   % green
    0.890 0.102 0.110; ...   % red
    1.000 0.498 0.000; ...   % orange
    0.416 0.239 0.604; ...   % purple
    0.694 0.349 0.157; ...   % brown
    0.651 0.808 0.890; ...   % light blue
    0.698 0.875 0.541; ...   % light green
    0.5505 0.0068 0.4520; ...% hawaii-purple from crameri v6
    0.6115 0.5872 0.1107; ...% hawaii-yellow from crameri v6
    0.7038 0.9490 0.9938];   % hawaii-blue from crameri v6

BG       = [0.97 0.97 0.98];
FONTNAME = 'Arial';
FONTSZ   = 11;

set(0,'DefaultAxesFontName',FONTNAME,'DefaultAxesFontSize',FONTSZ, ...
    'DefaultTextFontName',FONTNAME,'DefaultFigureColor',BG);

%% ── 1. IMPORT ────────────────────────────────────────────────────────────
fprintf('Importing data from %s ...\n', FILE);

opts = detectImportOptions(FILE, 'Sheet', SHEET);
opts.VariableNamesRange = 'A1';   % Row 1 = variable names
opts.DataRange          = 'A5';   % Rows 2-4 are section headers / hints

% Text columns — read as char to preserve mixed content
textCols = { ...
    'Patient_ID','Sex','Seizure_Type','Setting_SE_Onset', ...
    'Etiology_Specific','Etiology_Category','Comorbidities', ...
    'Prior_ASM1','Prior_ASM2','Prior_ASM3','Prior_ASM4','Prior_ASM5', ...
    'Benzo_Before_OXC','Benzo_Name_Dose','OXC_Setting', ...
    'OXC_Each_Load_Dose_mg','OXC_Load_Times_Given', ...
    'OXC_Maintenance_mg_per_day', ...
    'Concomitant_ASM1','Concomitant_ASM2','Concomitant_ASM3','Concomitant_ASM4', ...
    'Seizure_Cessation','Time_to_Cessation_min', ...
    'First_Dose_Response','First_Dose_Response_Desc', ...
    'Escalation_Required','Escalation_Agents','Overall_Efficacy', ...
    'EEG_Monitoring', ...
    'Na_Lowest_mEqL','Na_Lowest_day','Na_24h_mEqL','Na_48h_mEqL', ...
    'Hyponatremia_Occurred','Hyponatremia_Severity', ...
    'Other_Side_Effects','ICU_Admission','ICU_LOS_days', ...
    'Discharge_OXC_Dose_mg_per_day','Discharged_on_OXC', ...
    'Discharge_Disposition','Notes'};

for k = 1:numel(textCols)
    if any(strcmp(opts.VariableNames, textCols{k}))
        opts = setvartype(opts, textCols{k}, 'char');
    end
end

T = readtable(FILE, opts);

% Remove rows without a valid Patient_ID
if iscell(T.Patient_ID)
    hasID = ~cellfun(@isempty, T.Patient_ID) & ...
        ~cellfun(@(x) strcmpi(strtrim(x),'P000'), T.Patient_ID);
    T = T(hasID,:);
end

N = height(T);
fprintf('  Loaded %d patients.\n\n', N);

%% ── 2. CLEAN / RECODE ────────────────────────────────────────────────────
fprintf('Cleaning and recoding ...\n');

% ── 2a. Strip leading/trailing whitespace from all text columns
for k = 1:numel(textCols)
    vn = textCols{k};
    if ismember(vn, T.Properties.VariableNames) && iscell(T.(vn))
        T.(vn) = strtrim(T.(vn));
    end
end

% ── 2b. Standardise case-insensitive categorical fields
if ismember('Overall_Efficacy', T.Properties.VariableNames) && iscell(T.Overall_Efficacy)
    T.Overall_Efficacy = regexprep(T.Overall_Efficacy, '(?i)non.?responder',    'Non_Responder');
    T.Overall_Efficacy = regexprep(T.Overall_Efficacy, '(?i)partial.?responder','Partial_Responder');
    T.Overall_Efficacy = regexprep(T.Overall_Efficacy, '(?i)^responder$',        'Responder');
end

binaryCols = {'Benzo_Before_OXC','ICU_Admission','Discharged_on_OXC','Hyponatremia_Occurred','Escalation_Required'};
for k = 1:numel(binaryCols)
    vn = binaryCols{k};
    if ismember(vn, T.Properties.VariableNames) && iscell(T.(vn))
        T.(vn) = cellfun(@recodeYN, T.(vn), 'UniformOutput', false);
    end
end

% ── 2c. Parse numeric columns that may contain 'Unknown'/'N/A'/'No_Cessation'
numStrCols = {'Time_to_Cessation_min','ICU_LOS_days', ...
    'Discharge_OXC_Dose_mg_per_day', ...
    'Na_Lowest_mEqL','Na_Lowest_day','Na_24h_mEqL','Na_48h_mEqL'};
for k = 1:numel(numStrCols)
    vn = numStrCols{k};
    if ismember(vn, T.Properties.VariableNames) && iscell(T.(vn))
        T.(vn) = cellfun(@str2numSafe, T.(vn));
    end
end

% ── 2d. Total OXC loading dose
if ismember('Total_OXC_loading_dose_mg', T.Properties.VariableNames)
    raw = T.Total_OXC_loading_dose_mg;
    if iscell(raw)
        T.OXC_Total_Load_mg = cellfun(@str2numSafe, raw);
    else
        T.OXC_Total_Load_mg = raw;
    end
else
    eachStr = T.OXC_Each_Load_Dose_mg;
    timStr  = T.OXC_Load_Times_Given;
    each = cellfun(@(x) str2numSafe(strtrim(regexp(x,',','split','once'))), eachStr);
    tim  = cellfun(@str2numSafe, timStr);
    T.OXC_Total_Load_mg = each .* tim;
    warning('Total_OXC_loading_dose_mg column not found — using Each×Times fallback.');
end

% ── 2e. OXC maintenance dose numeric
if ismember('OXC_Maintenance_mg_per_day', T.Properties.VariableNames) && ...
        iscell(T.OXC_Maintenance_mg_per_day)
    T.OXC_Maint_num = cellfun(@str2numSafe, T.OXC_Maintenance_mg_per_day);
end

fprintf('  Cleaning complete.\n\n');

% DEFINE EFFICACY CATEGORIES (used by multiple figures & analyses) ──
effCats   = {'Responder','Partial_Responder','Non_Responder'};
effLabels = {'Responder','Partial Responder','Non-Responder'};
effColours = PALETTE([9 10 11],:);

%% ════════════════════════════════════════════════════════════════════════
%  FIGURE 1A — LENGTH OF STAY  (Hospital + ICU combined)
%% ════════════════════════════════════════════════════════════════════════
fprintf('--- Figure 1A: Length of Stay ---\n');
f1a = newFig('');

% Build combined data arrays for a grouped boxchart
hlos = T.Hospital_LOS_days;
hlos = hlos(~isnan(hlos));

if ismember('ICU_LOS_days', T.Properties.VariableNames)
    if iscell(T.ICU_LOS_days)
        iculos = cellfun(@str2numSafe, T.ICU_LOS_days);
    else
        iculos = T.ICU_LOS_days;
    end
    iculos = iculos(~isnan(iculos) & iculos > 0);
else
    iculos = [];
end

allVals  = [hlos(:);  iculos(:)];
allGrp   = [repmat({'Hospital LOS'}, numel(hlos),  1); ...
    repmat({'ICU LOS'},       numel(iculos), 1)];
catGrp   = categorical(allGrp, {'Hospital LOS','ICU LOS'});
bc = boxchart(allVals, 'GroupByColor', catGrp);
bc(1).BoxFaceColor = PALETTE(1,:);  bc(1).MarkerColor = PALETTE(1,:);
bc(1).BoxWidth=.75;
bc(2).BoxWidth=.75;
ax=gca;
ax.Box = 'off'; ax.YGrid = 'on'; ax.GridAlpha = 0.3;
ax.XTick=[];
ax.FontSize = 20;
f1a.Position = [50 50 400 550];

print(fullfile(FIGDIR,'Fig1A_LengthOfStay.png'),'-dpng','-r300')

%% ════════════════════════════════════════════════════════════════════════
%  FIGURE 1B — OXC LOADING DOSE (mg/kg)
%% ════════════════════════════════════════════════════════════════════════
fprintf('--- Figure 1B: OXC Loading Dose mg/kg ---\n');
f1b = newFig('');

ax = axes('Parent', f1b);
if ismember('OXC_loading_dose_mgkg', T.Properties.VariableNames)
    mgkg = T.OXC_loading_dose_mgkg(~isnan(T.OXC_loading_dose_mgkg));
    if ~isempty(mgkg)
        histogram(ax, mgkg, 'BinWidth',3, 'FaceColor',PALETTE(4,:), ...
            'EdgeColor','w','LineWidth',1);
        xlabel(ax,'Loading Dose (mg/kg)'); ylabel(ax,'Count');
        % Median line: black (changed from red)
        hxl = xline(ax, median(mgkg),'--k','LineWidth',1.5, ...
            'Label', sprintf('Median = %.1f mg/kg', median(mgkg)), ...
            'LabelHorizontalAlignment','right');
        hxl.FontSize = 16;
        ax.Box='off'; ax.YGrid='on'; ax.GridAlpha=0.3;
    end
end
ax.FontSize = 20;

print(fullfile(FIGDIR,'Fig1B_OXC_LoadDose_mgkg.png'),'-dpng','-r300')

%% ════════════════════════════════════════════════════════════════════════
%  FIGURE 2A — EFFICACY SUMMARY
%  Three 100%-stacked horizontal bars in one axes, one row per measure.for
%  Top: Seizure cessation, Middle: first dose response and Bottom: further
%  escalation needed.
%% ════════════════════════════════════════════════════════════════════════
fprintf('--- Figure 2A: Efficacy Summary ---\n');
rowLabels = {'Seizure Cessation', 'First Dose Response', 'Further Escalation Needed'};

% Collect counts for each row
% Row 1: Seizure Cessation (Yes / Partial / No)
if iscell(T.Seizure_Cessation)
    scCnts = cellfun(@(s) sum(strcmpi(T.Seizure_Cessation, s)), {'Yes','Partial','No'});
else
    scCnts = [0 0 0];
end
% Row 2: First Dose Response (Yes / Partial / No)
if iscell(T.First_Dose_Response)
    fdCnts = cellfun(@(s) sum(strcmpi(T.First_Dose_Response, s)), {'Yes','No'});
else
    fdCnts = [0 0 0];
end
% Row 3: Further Escalation Needed (Yes / No — mapped to cols 1 & 3 for red/green)
if iscell(T.Escalation_Required)
    escY = sum(strcmpi(T.Escalation_Required,'Yes'));
    escN = sum(strcmpi(T.Escalation_Required,'No'));
    escCnts = [escY, 0, escN];   % col 1=green(No escalation), col 3=red(Escalation needed)
else
    escCnts = [0 0 0];
end

allRows   = [escCnts; [fdCnts(1),0,fdCnts(2)]; scCnts]./0.23;

% 2. Create the horizontal stacked bar chart
newFig('');
hbar = barh(allRows, 'stacked');
hbar(1).BarWidth=0.6;
grid on;
hbar(1).FaceColor='flat';hbar(1).CData = [PALETTE(8,:);PALETTE(8,:);PALETTE(9,:)];
hbar(2).FaceColor='flat';hbar(2).CData = [PALETTE(8,:);PALETTE(8,:);PALETTE(10,:)];
hbar(3).FaceColor='flat';hbar(3).CData = [PALETTE(3,:);PALETTE(3,:);PALETTE(11,:)];
ax=gca;

xlim(ax, [0 100]);
ylim(ax, [0.4 3.6]);
ax.Box   = 'off';
ax.YGrid = 'off';
ax.XGrid = 'on';
ax.GridAlpha = 0.25;
ax.XTick=[];
ax.YTick=[];
ax.FontSize=20;

print(fullfile(FIGDIR,'Fig2A_EfficacySummary.png'),'-dpng','-r300')

%% ════════════════════════════════════════════════════════════════════════
%  FIGURE 2B — LOS COMPARISON BY EFFICACY GROUP  (secondary outcome)
%% ════════════════════════════════════════════════════════════════════════
fprintf('--- Figure 2B: LOS by Efficacy Group ---\n');
newFig('');

% Hospital LOS
ax = subplot(1,2,1);
if iscell(T.Overall_Efficacy)
    losData = {}; losGrp = {};
    grpLabels = {'Responder','Partial Responder','Non-Responder'};
    for k = 1:3
        mask = strcmpi(T.Overall_Efficacy, effCats{k});
        vals = T.Hospital_LOS_days(mask);
        vals = vals(~isnan(vals));
        if ~isempty(vals)
            losData{end+1} = vals;
        end
        losGrp = [losGrp; repmat(grpLabels(k), sum(mask & ~isnan(T.Hospital_LOS_days)), 1)]; 
    end
    allVals = vertcat(losData{:});   % each element is already a column vector
    catGrp  = categorical(losGrp, grpLabels);
    if ~isempty(allVals)
        boxchart(ax, catGrp, allVals(:), 'GroupByColor',catGrp,'BoxWidth',2.7,'BoxFaceAlpha',0.7);
        colororder(PALETTE(9:11,:))
        ax.Box='off'; ax.YGrid='on';
    end
end
ax.FontSize = 20;
ax.XTick=[];

% ICU LOS
ax = subplot(1,2,2);
if iscell(T.Overall_Efficacy) && ismember('ICU_LOS_days', T.Properties.VariableNames)
    if iscell(T.ICU_LOS_days)
        icuLOS_num = cellfun(@str2numSafe, T.ICU_LOS_days);
    else
        icuLOS_num = T.ICU_LOS_days;
    end
    losData2 = {}; losGrp2 = {};
    for k = 1:3
        mask = strcmpi(T.Overall_Efficacy, effCats{k});
        vals = icuLOS_num(mask);
        vals = vals(~isnan(vals) & vals > 0);
        if ~isempty(vals)
            losData2{end+1} = vals;
        end
        nValid = sum(mask & ~isnan(icuLOS_num) & icuLOS_num > 0);
        losGrp2 = [losGrp2; repmat(grpLabels(k), nValid, 1)]; 
    end
    if ~isempty(losGrp2)
        allVals2 = vertcat(losData2{:});   % each element already a column vector
        catGrp2  = categorical(losGrp2, grpLabels);
        boxchart(ax, catGrp2, allVals2(:), 'GroupByColor',catGrp2,'BoxWidth',2.7,'BoxFaceAlpha',0.7);
        colororder(PALETTE(9:11,:))
        ax.Box='off'; ax.YGrid='on';
    end
end
ax.FontSize = 20;
ax.XTick=[];

print(fullfile(FIGDIR,'Fig2B_LOS_byEfficacy.png'),'-dpng','-r300')

%% ════════════════════════════════════════════════════════════════════════
%  FIGURE 3 — SODIUM TRAJECTORY
%% ════════════════════════════════════════════════════════════════════════
fprintf('--- Figure 3: Sodium Trajectory ---\n');
f3 = newFig('');

ax = axes('Parent', f3);
naVars   = {'Na_Baseline_mEqL','Na_24h_mEqL','Na_48h_mEqL','Na_Lowest_mEqL'};
naLabels = {'Baseline','24h','48h','Lowest'};
naData = []; naGroup = {};
for k = 1:numel(naVars)
    vn = naVars{k};
    if ismember(vn, T.Properties.VariableNames)
        raw = T.(vn);
        if iscell(raw), vals = cellfun(@str2numSafe, raw); else, vals = raw; end
        vals = vals(~isnan(vals));
        naData  = [naData;  vals(:)];
        naGroup = [naGroup; repmat({naLabels{k}}, numel(vals), 1)];
    end
end
if ~isempty(naData)
    boxchart(ax, categorical(naGroup, naLabels), naData, ...
        'BoxFaceColor',PALETTE(1,:),'MarkerColor',PALETTE(1,:));
    % Na = 135 dotted line
    yline(ax, 135, '--r', 'LineWidth',1.5);
    % Na = 145 dotted line
    yline(ax, 145, '--', 'Color',[0.5 0.5 0.5], 'LineWidth',1.5);
    ylabel(ax,'Sodium (mEq/L)');
    ax.Box='off'; ax.YGrid='on'; ax.GridAlpha=0.3;
    % Add a manual legend entry for the 135 line since we removed its label
    hold(ax,'on');
    h135 = plot(ax, NaN, NaN, '--r', 'LineWidth',1.5);
    h145 = plot(ax, NaN, NaN, '--', 'Color',[0.5 0.5 0.5], 'LineWidth',1.5);
    hold(ax,'off');
    % legend(ax, [h135, h145], {'Na = 135 mEq/L','Na = 145 mEq/L'}, ...
    %        'Location','best','FontSize',9,'Box','off');
end
ax.FontSize = 20;

print(fullfile(FIGDIR,'Fig3_SodiumTrajectory.png'),'-dpng','-r300')

%% ════════════════════════════════════════════════════════════════════════
%  SUPPLEMENTARY FIGURE — PRIOR MEDS
%% ════════════════════════════════════════════════════════════════════════
fprintf('--- Supplementary Figure: Prior ASMs / Benzo / Concomitant ASMs ---\n');

% Panel A: Prior ASM Count histogram
ax4 = subplot(1,2,1);
if ismember('Prior_ASM_Count', T.Properties.VariableNames)
    pc = T.Prior_ASM_Count(~isnan(T.Prior_ASM_Count));
    if ~isempty(pc)
        histogram(ax4, pc, 'BinEdges',-0.5:1:max(pc)+0.5, 'FaceColor',PALETTE(2,:), ...
            'EdgeColor','w','LineWidth',1);
        % xlabel(ax4,'Number of Prior ASMs'); ylabel(ax4,'Count');
        % title(ax4,'Prior ASMs Before OXC','FontWeight','bold');
        ax4.XTick = 0:max(pc);
        ax4.Box='off'; ax4.YGrid='on'; ax4.GridAlpha=0.3;
    end
end
ax4.FontSize = 20;

% Panel B: Other Maintenance ASM count (concomitant agents per patient)
ax6 = subplot(1,2,2);
casmCols = {'Other_Maintenance_ASM1','Other_Maintenance_ASM2', ...
            'Other_Maintenance_ASM3','Other_Maintenance_ASM4'};
if ~any(ismember(casmCols, T.Properties.VariableNames))
    % Fallback to the column names actually produced by the import step
    casmCols = {'Concomitant_ASM1','Concomitant_ASM2','Concomitant_ASM3','Concomitant_ASM4'};
end
avail = casmCols(ismember(casmCols, T.Properties.VariableNames));
if ~isempty(avail)
    casmCount = zeros(N,1);
    for k = 1:numel(avail)
        col = T.(avail{k});
        if iscell(col)
            casmCount = casmCount + double(~cellfun(@isempty,col) & ...
                ~cellfun(@(x) strcmpi(x,'None'), col));
        end
    end
    histogram(ax6, casmCount, 'BinEdges',-0.5:1:max(casmCount)+0.5, ...
        'FaceColor',PALETTE(5,:),'EdgeColor','w','LineWidth',1);
    % xlabel(ax6,'Number of Other Maintenance ASMs'); ylabel(ax6,'Count');
    % title(ax6,'Other Maintenance ASMs at OXC Load','FontWeight','bold');
    ax6.XTick = 0:max(casmCount);
    ax6.Box='off'; ax6.YGrid='on'; ax6.GridAlpha=0.3;
end
ax6.FontSize = 20;

print(fullfile(FIGDIR,'FigS1_Prior-ASMs.png'),'-dpng','-r300')

%% ════════════════════════════════════════════════════════════════════════
%  STATISTICAL ANALYSES
%% ════════════════════════════════════════════════════════════════════════
fprintf('\n');
fprintf('=================================================================\n');
fprintf('  EXPLORATORY ANALYSES — OXC Focal SE  (N=%d)\n', N);
fprintf('  All tests are exploratory / hypothesis-generating.\n');
fprintf('=================================================================\n\n');

%% Seizure Type × Responder Class ───────────────────────
fprintf('--- Seizure Type vs Responder Class ---\n');
if iscell(T.Seizure_Type) && iscell(T.Overall_Efficacy)
    stCats = {'Focal_Motor','Focal_Non-motor','Focal_to_Bilateral'};
    stLbl  = {'Focal Motor','Focal Non-Motor','Focal->Bilateral TC'};
    contMat = zeros(numel(stCats), 3);
    for si = 1:numel(stCats)
        mask = strcmpi(T.Seizure_Type, stCats{si});
        for fi = 1:3
            contMat(si,fi) = sum(strcmpi(T.Overall_Efficacy(mask), effCats{fi}));
        end
    end
    hasRow   = any(contMat, 2);
    contMat2 = contMat(hasRow,:);
    stLbl2   = stLbl(hasRow);

    fprintf('  Contingency table (rows=Seizure Type, cols=Responder/Partial/Non-Responder):\n');
    fprintf('  %-22s  %10s  %18s  %15s\n','','Responder','Partial Responder','Non-Responder');
    for si = 1:size(contMat2,1)
        fprintf('  %-22s  %10d  %18d  %15d\n', stLbl2{si}, contMat2(si,1), contMat2(si,2), contMat2(si,3));
    end

    % Chi-square test of independence (3-class outcome; Fisher not applicable)
    [chi2stat, p_chi2, df_chi2, expMat] = chi2gof_table(contMat2);
    pctSmall = mean(expMat(:) < 5) * 100;
    fprintf('  Chi-square = %.3f  df = %d  p = %.4f\n', chi2stat, df_chi2, p_chi2);
    fprintf('  Note: %.0f%% of expected cells < 5 — interpret with caution given small N.\n\n', pctSmall);
end

%% Hospital LOS × Responder Class 
fprintf('--- Hospital LOS vs Responder Class ---\n');
if iscell(T.Overall_Efficacy)
    grpData = cell(1,3);
    for k = 1:3
        mask = strcmpi(T.Overall_Efficacy, effCats{k});
        vals = T.Hospital_LOS_days(mask);
        grpData{k} = vals(~isnan(vals));
        fprintf('  %-22s  n=%d  Median=%.1f  IQR=[%.1f-%.1f]\n', ...
            effLabels{k}, numel(grpData{k}), ...
            median(grpData{k}), prctile(grpData{k},25), prctile(grpData{k},75));
    end
    % Kruskal-Wallis across 3 groups
    allVals = vertcat(grpData{:});
    allGrp  = [repmat(effLabels(1), numel(grpData{1}), 1); ...
        repmat(effLabels(2), numel(grpData{2}), 1); ...
        repmat(effLabels(3), numel(grpData{3}), 1)];
    if numel(allVals) >= 3
        [p_kw, tbl_kw] = kruskalwallis(allVals, allGrp, 'off');
        fprintf('  Kruskal-Wallis H = %.3f  df = %d  p = %.4f\n\n', ...
            tbl_kw{2,5}, tbl_kw{2,3}, p_kw);
    else
        fprintf('  Insufficient data for Kruskal-Wallis.\n\n');
    end
end

%% ICU LOS × Responder Class
fprintf('--- ICU LOS vs Responder Class ---\n');
if iscell(T.Overall_Efficacy) && ismember('ICU_LOS_days', T.Properties.VariableNames)
    if iscell(T.ICU_LOS_days)
        icuLOS_num = cellfun(@str2numSafe, T.ICU_LOS_days);
    else
        icuLOS_num = T.ICU_LOS_days;
    end
    grpData = cell(1,3);
    for k = 1:3
        mask = strcmpi(T.Overall_Efficacy, effCats{k});
        vals = icuLOS_num(mask);
        grpData{k} = vals(~isnan(vals) & vals > 0);
        fprintf('  %-22s  n=%d  Median=%.1f  IQR=[%.1f-%.1f]\n', ...
            effLabels{k}, numel(grpData{k}), ...
            median(grpData{k}), prctile(grpData{k},25), prctile(grpData{k},75));
    end
    allVals = vertcat(grpData{:});
    allGrp  = [repmat(effLabels(1), numel(grpData{1}), 1); ...
        repmat(effLabels(2), numel(grpData{2}), 1); ...
        repmat(effLabels(3), numel(grpData{3}), 1)];
    if numel(allVals) >= 3
        [p_kw, tbl_kw] = kruskalwallis(allVals, allGrp, 'off');
        fprintf('  Kruskal-Wallis H = %.3f  df = %d  p = %.4f\n\n', ...
            tbl_kw{2,5}, tbl_kw{2,3}, p_kw);
    else
        fprintf('  Insufficient data for Kruskal-Wallis.\n\n');
    end
end

%% Loading Dose (mg/kg) × Hyponatremia (Yes/No)
fprintf('--- OXC Loading Dose mg/kg vs Hyponatremia ---\n');
if ismember('OXC_loading_dose_mgkg', T.Properties.VariableNames) && ...
        iscell(T.Hyponatremia_Occurred)
    hypY = strcmpi(T.Hyponatremia_Occurred,'Yes');
    hypN = strcmpi(T.Hyponatremia_Occurred,'No');
    doseY = T.OXC_loading_dose_mgkg(hypY);
    doseN = T.OXC_loading_dose_mgkg(hypN);
    doseY = doseY(~isnan(doseY));
    doseN = doseN(~isnan(doseN));
    fprintf('  Hyponatremia Yes (n=%d): Median=%.1f mg/kg  IQR=[%.1f-%.1f]\n', ...
        numel(doseY), median(doseY), prctile(doseY,25), prctile(doseY,75));
    fprintf('  Hyponatremia No  (n=%d): Median=%.1f mg/kg  IQR=[%.1f-%.1f]\n', ...
        numel(doseN), median(doseN), prctile(doseN,25), prctile(doseN,75));
    if numel(doseY) >= 2 && numel(doseN) >= 2
        p_rs = ranksum(doseY, doseN);
        fprintf('  Wilcoxon rank-sum p = %.4f\n\n', p_rs);
    else
        fprintf('  Insufficient data for Wilcoxon rank-sum.\n\n');
    end
end

%% Etiology Category × Responder Class
fprintf('--- Etiology Category vs Responder Class ---\n');
if iscell(T.Etiology_Category) && iscell(T.Overall_Efficacy)
    eCatsFull = {'Structural','Metabolic','Infectious','Immune','Unknown','Other'};
    contMat = zeros(numel(eCatsFull), 3);
    for ei = 1:numel(eCatsFull)
        mask = strcmpi(T.Etiology_Category, eCatsFull{ei});
        for fi = 1:3
            contMat(ei,fi) = sum(strcmpi(T.Overall_Efficacy(mask), effCats{fi}));
        end
    end
    hasRow   = any(contMat, 2);
    contMat2 = contMat(hasRow,:);
    eLbl2    = eCatsFull(hasRow);

    fprintf('  Contingency table (rows=Etiology, cols=Responder/Partial/Non-Responder):\n');
    fprintf('  %-15s  %10s  %18s  %15s\n','','Responder','Partial Responder','Non-Responder');
    for ei = 1:size(contMat2,1)
        fprintf('  %-15s  %10d  %18d  %15d\n', eLbl2{ei}, contMat2(ei,1), contMat2(ei,2), contMat2(ei,3));
    end

    % Chi-square test of independence (3-class outcome; Fisher not applicable)
    [chi2stat, p_chi2, df_chi2, expMat] = chi2gof_table(contMat2);
    fprintf('  Chi-square = %.3f  df = %d  p = %.4f\n', chi2stat, df_chi2, p_chi2);
end

%% First Dose Response × Responder Class

fprintf('\n--- First Dose Response vs Responder Class ---\n');
if iscell(T.First_Dose_Response) && iscell(T.Overall_Efficacy)
    fdCats = {'Yes','No'};
    fdLbl  = {'First Dose Yes','First Dose No'};
    contMat = zeros(numel(fdCats), 2);
    for fi = 1:numel(fdCats)
        mask = strcmpi(T.First_Dose_Response, fdCats{fi});
        for ri = 1:3
            contMat(fi,ri) = sum(strcmpi(T.Overall_Efficacy(mask), effCats{ri}));
        end
    end
    hasRow   = any(contMat, 2);
    contMat2 = contMat(hasRow,:);
    fdLbl2   = fdLbl(hasRow);

    fprintf('  Contingency table (rows=First Dose Response, cols=Responder/Non-Responder):\n');
    fprintf('  %-22s  %10s  %18s  %15s\n','','Responder','Partial Responder','Non-Responder');
    for fi = 1:size(contMat2,1)
        fprintf('  %-22s  %10d  %18d  %15d\n', fdLbl2{fi}, contMat2(fi,1), contMat2(fi,2), contMat2(fi,3));
    end

    % Chi-square test of independence (3-class outcome; Fisher not applicable)
    [chi2stat, p_chi2, df_chi2, expMat] = chi2gof_table(contMat2);
    fprintf('  Chi-square = %.3f  df = %d  p = %.4f\n', chi2stat, df_chi2, p_chi2);
end

%% Hyponatremia x Hospital LOS
fprintf('\n\n--- Hyponatremia vs Hospital LOS ---\n');
los  = T.Hospital_LOS_days;
hypo = strtrim(T.Hyponatremia_Occurred);

losY = los(strcmpi(hypo,'Yes') & ~isnan(los));
losN = los(strcmpi(hypo,'No')  & ~isnan(los));

% DESCRIPTIVE STATS
fprintf('Hyponatremia Yes (n=%d): Median=%.1f  IQR=[%.1f–%.1f]  Range=[%.0f–%.0f]\n', ...
    numel(losY), median(losY), prctile(losY,25), prctile(losY,75), min(losY), max(losY));
fprintf('Hyponatremia No  (n=%d): Median=%.1f  IQR=[%.1f–%.1f]  Range=[%.0f–%.0f]\n', ...
    numel(losN), median(losN), prctile(losN,25), prctile(losN,75), min(losN), max(losN));

% WILCOXON RANK-SUM TEST
[p, h] = ranksum(losY, losN);
fprintf('\nWilcoxon rank-sum:  p = %.4f  (h = %d)\n', p, h);

%% Etiology Category × Hyponatremia (Yes/No)
fprintf('\n\n--- Etiology Category vs Hyponatremia ---\n');
if iscell(T.Etiology_Category) && iscell(T.Hyponatremia_Occurred)
    eCatsFull = {'Structural','Metabolic','Infectious','Immune','Unknown','Other'};
    contMat = zeros(numel(eCatsFull), 2);
    for ei = 1:numel(eCatsFull)
        mask = strcmpi(T.Etiology_Category, eCatsFull{ei});
        contMat(ei,1) = sum(strcmpi(T.Hyponatremia_Occurred(mask), 'Yes'));
        contMat(ei,2) = sum(strcmpi(T.Hyponatremia_Occurred(mask), 'No'));
    end
    hasRow   = any(contMat, 2);
    contMat2 = contMat(hasRow,:);
    eLbl2    = eCatsFull(hasRow);

    fprintf('  Contingency table (rows=Etiology, cols=Hyponatremia Yes/No):\n');
    fprintf('  %-15s  %20s  %20s  %10s\n','','Hyponatremia Yes','Hyponatremia No','Row Total');
    for ei = 1:size(contMat2,1)
        fprintf('  %-15s  %20d  %20d  %10d\n', ...
            eLbl2{ei}, contMat2(ei,1), contMat2(ei,2), sum(contMat2(ei,:)));
    end
    fprintf('  %-15s  %20d  %20d  %10d\n', ...
        'Total', sum(contMat2(:,1)), sum(contMat2(:,2)), sum(contMat2(:)));

    % Chi-square (N×2 table)
    [chi2stat, p_chi2, df_chi2, expMat] = chi2gof_table(contMat2);
    pctSmall = mean(expMat(:) < 5) * 100;
    fprintf('  Chi-square = %.3f  df = %d  p = %.4f\n', chi2stat, df_chi2, p_chi2);
    fprintf('  Note: %.0f%% of expected cells < 5 — interpret with caution given small N.\n\n', pctSmall);
end

%% Setting of SE Onset × Responder Class
fprintf('\n--- Setting of SE Onset vs Responder Class ---\n');
if ismember('Setting_SE_Onset', T.Properties.VariableNames) && ...
   ismember('Overall_Efficacy', T.Properties.VariableNames) && ...
   iscell(T.Setting_SE_Onset) && iscell(T.Overall_Efficacy)

    % Extract unique non-empty onset categories
    onsetCats = unique(T.Setting_SE_Onset(~cellfun(@isempty, T.Setting_SE_Onset)));

    % Build contingency matrix (rows = SE Onset Setting, cols = Responder/Partial/Non-Responder)
    contMat = zeros(numel(onsetCats), 3);
    for oi = 1:numel(onsetCats)
        mask = strcmpi(T.Setting_SE_Onset, onsetCats{oi});
        for fi = 1:3
            contMat(oi,fi) = sum(strcmpi(T.Overall_Efficacy(mask), effCats{fi}));
        end
    end

    % Filter out empty rows
    hasRow    = any(contMat, 2);
    contMat2  = contMat(hasRow,:);
    onsetLbl2 = onsetCats(hasRow);

    % Print contingency table
    fprintf('  Contingency table (rows=SE Onset Setting, cols=Responder/Partial/Non-Responder):\n');
    fprintf('  %-22s  %10s  %18s  %15s  %10s\n', '', 'Responder', 'Partial Responder', 'Non-Responder', 'Total');
    for oi = 1:size(contMat2, 1)
        fprintf('  %-22s  %10d  %18d  %15d  %10d\n', ...
            onsetLbl2{oi}, contMat2(oi,1), contMat2(oi,2), contMat2(oi,3), sum(contMat2(oi,:)));
    end
    fprintf('  %-22s  %10d  %18d  %15d  %10d\n', ...
        'Total', sum(contMat2(:,1)), sum(contMat2(:,2)), sum(contMat2(:,3)), sum(contMat2(:)));

    % Chi-square test of independence
    [chi2stat, p_chi2, df_chi2, expMat] = chi2gof_table(contMat2);
    pctSmall = mean(expMat(:) < 5) * 100;
    fprintf('\n  Chi-square = %.3f  df = %d  p = %.4f\n', chi2stat, df_chi2, p_chi2);
    fprintf('  Note: %.0f%% of expected cells < 5 — interpret with caution given small N.\n\n', pctSmall);
else
    fprintf('  Required columns (Setting_SE_Onset, Overall_Efficacy) not found or not cell arrays.\n\n');
end

%% Setting of SE Onset (Prior to Arrival vs In-Hospital) × Responder Class
fprintf('\n--- Setting of SE Onset (Prior to Arrival vs In-Hospital) vs Responder Class ---\n');
if ismember('Setting_SE_Onset', T.Properties.VariableNames) && ...
   ismember('Overall_Efficacy', T.Properties.VariableNames) && ...
   iscell(T.Setting_SE_Onset) && iscell(T.Overall_Efficacy)

    % 1. Binary Recoding Logic
    settingBinary = cell(height(T), 1);
    for i = 1:height(T)
        s = lower(strtrim(T.Setting_SE_Onset{i}));
        if contains(s, 'prior_to_arrival')
            settingBinary{i} = 'Prior to Arrival';
        elseif contains(s, 'ed') || contains(s, 'icu') || contains(s, 'floor') || contains(s, 'outside_hospital') % ED | ICU | Floor | Outside_Hospital
            settingBinary{i} = 'In-Hospital';
        else
            settingBinary{i} = T.Setting_SE_Onset{i}; % preserve exact label if unclassified
        end
    end

    onsetGroupCats = {'Prior to Arrival', 'In-Hospital'};
    
    % 2. Build Contingency Matrix (2 rows × 3 columns)
    contMat = zeros(2, 3);
    for oi = 1:2
        mask = strcmpi(settingBinary, onsetGroupCats{oi});
        for fi = 1:3
            contMat(oi,fi) = sum(strcmpi(T.Overall_Efficacy(mask), effCats{fi}));
        end
    end

    % 3. Print Contingency Table
    fprintf('  Contingency table (rows=Onset Location Group, cols=Responder Class):\n');
    fprintf('  %-22s  %10s  %18s  %15s  %10s\n', '', 'Responder', 'Partial Responder', 'Non-Responder', 'Total');
    for oi = 1:2
        fprintf('  %-22s  %10d  %18d  %15d  %10d\n', ...
            onsetGroupCats{oi}, contMat(oi,1), contMat(oi,2), contMat(oi,3), sum(contMat(oi,:)));
    end
    fprintf('  %-22s  %10d  %18d  %15d  %10d\n', ...
        'Total', sum(contMat(:,1)), sum(contMat(:,2)), sum(contMat(:,3)), sum(contMat(:)));

    % 4. Chi-Square Test of Independence
    [chi2stat, p_chi2, df_chi2, expMat] = chi2gof_table(contMat);
    pctSmall = mean(expMat(:) < 5) * 100;
    fprintf('\n  Chi-square = %.3f  df = %d  p = %.4f\n', chi2stat, df_chi2, p_chi2);
    fprintf('  Note: %.0f%% of expected cells < 5 — interpret with caution given small N.\n\n', pctSmall);
else
    fprintf('  Required columns (Setting_SE_Onset, Overall_Efficacy) not found or not cell arrays.\n\n');
end

%% THE END
fprintf('=================================================================\n');
fprintf('All figures saved to: %s\n', FIGDIR);
fprintf('v6 analysis complete.\n');

%% ════════════════════════════════════════════════════════════════════════
%  LOCAL HELPER FUNCTIONS
%% ════════════════════════════════════════════════════════════════════════

function v = str2numSafe(x)
% Convert char/numeric/cell to double; return NaN for non-numeric strings
if isnumeric(x),  v = x; return; end
if ischar(x)
    n = str2double(x);
    if isnan(n), v = NaN; else, v = n; end
else
    v = NaN;
end
end

function out = recodeYN(x)
% Map various spellings of Yes/No to canonical 'Yes'/'No'
if strcmpi(strtrim(x),'yes') || strcmpi(strtrim(x),'y')
    out = 'Yes';
elseif strcmpi(strtrim(x),'no') || strcmpi(strtrim(x),'n')
    out = 'No';
else
    out = strtrim(x);
end
end

function f = newFig(titleStr)
f = figure('Color',[0.97 0.97 0.98],'Position',[0 0 500 500]);
sgtitle(titleStr,'FontSize',13,'FontWeight','bold','FontName','Arial');
end

function [chi2stat, p, df, expected] = chi2gof_table(ctable)
% Chi-square test of independence for a contingency table.
% Returns chi2 statistic, p-value, degrees of freedom, expected cell matrix.
observed = double(ctable);
rowSums  = sum(observed, 2);
colSums  = sum(observed, 1);
total    = sum(rowSums);
expected = rowSums * colSums / total;
df       = (size(observed,1)-1) * (size(observed,2)-1);
chi2stat = sum(sum((observed - expected).^2 ./ max(expected, 1e-10)));
p        = 1 - chi2cdf(chi2stat, df);
end
