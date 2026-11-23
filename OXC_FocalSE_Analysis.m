%% ========================================================================
%  OXC_FocalSE_Analysis.m 
%  ------------------------------------------------------------------------
%  Efficacy and safety of an oral oxcarbazepine (OXC) loading dose in focal
%  status epilepticus: retrospective single-center case series.
%
%  INPUT   OXC_FocalSE_AnalysisData.xlsx   (sheet 'Data', one row per patient;
%          created from the master workbook)
%  OUTPUT  output/tables/OXC_Supplementary_ContingencyTables.xlsx
%          output/figures/*.png
%          a printout of every number reported in the manuscript
%
%  DEFINITIONS
%    Responder          seizures stopped AND no further ASM escalation
%    Partial responder  ASM escalation required AND seizure frequency decreased
%    Non-responder      no decrease in seizure frequency
%    First-dose response Full | Partial | None
%    Concomitant agents include anesthetics (propofol, ketamine, midazolam)
%
%  STATISTICS
%    Continuous variables: median (IQR; range). IQR = MATLAB prctile
%      (default, Hazen definition).
%    Categorical variables: n (%), with Clopper-Pearson 95% confidence intervals
%      for key proportions.
%    Categorical associations: Fisher-Freeman-Halton exact test (full
%      enumeration of all tables with the observed margins).
%    Continuous vs categorical: Kruskal-Wallis (three groups), Wilcoxon
%      rank-sum (two groups).
%    All tests are exploratory; no correction for multiple testing.
%
%  REQUIREMENTS
%    MATLAB R2020a or later with the Statistics and Machine Learning Toolbox
%    (prctile, binofit, kruskalwallis, ranksum, boxchart).
%
%  HOW TO RUN
%    1. Put this script and OXC_FocalSE_AnalysisData.xlsx in one folder.
%    2. Run the script. Results appear in the Command Window and in ./output.
%% ========================================================================

clear; clc; close all;

%% 0. SETTINGS ------------------------------------------------------------
FILE   = 'OXC_FocalSE_AnalysisData.xlsx';
SHEET  = 'Data';
OUTDIR = 'output';
FIGDIR = fullfile(OUTDIR, 'figures');
TBLDIR = fullfile(OUTDIR, 'tables');
XLSX_CONT = fullfile(TBLDIR, 'OXC_Supplementary_ContingencyTables.xlsx');

if ~exist(FIGDIR,'dir'), mkdir(FIGDIR); end
if ~exist(TBLDIR,'dir'), mkdir(TBLDIR); end

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

% Efficacy categories (used by several analyses and figures)
effCats    = {'Responder','Partial_Responder','Non_Responder'};
effLabels  = {'Responder','Partial Responder','Non-Responder'};
respLbl    = effLabels;

%% 1. LOAD AND VALIDATE ---------------------------------------------------
fprintf('OXC focal SE analysis | MATLAB %s | %s\n', version, datestr(now,'yyyy-mm-dd HH:MM'));
fprintf('Input: %s (sheet %s)\n', FILE, SHEET);
T = readtable(FILE, 'Sheet', SHEET, 'TextType', 'char');
N = height(T);
fprintf('  %d patients, %d columns.\n\n', N, width(T));

required = {'Patient','Age_years','Sex','Weight_kg','Seizure_Type','Setting_SE_Onset', ...
    'SE_Onset_Prior_to_Arrival','Day_SE_Onset_from_Admission','Etiology_Category','SAH_TBI', ...
    'Prior_ASM_Count','Benzo_Before_OXC','OXC_Setting','OXC_Load_Administrations', ...
    'OXC_Total_Load_mg','OXC_Load_mg_per_kg','Day_OXC_from_Admission','Days_SE_Onset_to_OXC', ...
    'OXC_Maintenance_Started','OXC_Maintenance_mg_per_day','Concomitant_Agents', ...
    'Concomitant_ASM_Count','Concomitant_Anesthetic','Seizure_Cessation','First_Dose_Response', ...
    'Escalation_Required','Escalation_Agents','Overall_Efficacy','Na_Baseline_mEqL','Na_24h_mEqL', ...
    'Na_48h_mEqL','Na_Lowest_mEqL','Na_Lowest_day','Na_Decrease_mEqL','Hyponatremia', ...
    'Hyponatremia_Severity','Baseline_Na_Low','New_Onset_Hyponatremia','ICU_Admission', ...
    'ICU_LOS_days','Hospital_LOS_days','Discharge_Disposition','In_Hospital_Death', ...
    'Discharged_on_OXC','Discharge_OXC_mg_per_day'};
missing = required(~ismember(required, T.Properties.VariableNames));
if ~isempty(missing)
    error('Input workbook is missing column(s): %s', strjoin(missing, ', '));
end
PID = T.Patient;

% ── integrity checks
fprintf('=== DATA CHECKS ===\n');
esc    = strcmp(T.Escalation_Required,'Yes');
isCess = strcmp(T.Seizure_Cessation,'Yes');  isPart = strcmp(T.Seizure_Cessation,'Partial');
isNone = strcmp(T.Seizure_Cessation,'No');
derived = repmat({'UNDEFINED'}, N, 1);
derived(isCess & ~esc)           = {'Responder'};
derived((isCess | isPart) & esc) = {'Partial_Responder'};
derived(isNone)                  = {'Non_Responder'};
reportCheck('Overall_Efficacy agrees with Seizure_Cessation + Escalation_Required', ~strcmp(derived, T.Overall_Efficacy), PID);
reportCheck('First_Dose_Response is Full / Partial / None', ~ismember(T.First_Dose_Response, {'Full','Partial','None'}), PID);
reportCheck('Overall_Efficacy uses the three expected categories', ~ismember(T.Overall_Efficacy, effCats), PID);
reportCheck('Loading dose is above 15 mg/kg', T.OXC_Load_mg_per_kg <= 15, PID);
reportCheck('Hyponatremia flag agrees with lowest sodium (below 135)', (T.Na_Lowest_mEqL < 135) ~= strcmp(T.Hyponatremia,'Yes'), PID);
fprintf('\n');

ov      = T.Overall_Efficacy;
isR     = strcmp(ov,'Responder');
isP     = strcmp(ov,'Partial_Responder');
isNR    = strcmp(ov,'Non_Responder');
dead    = strcmp(T.In_Hospital_Death,'Yes');
icuPt   = strcmp(T.ICU_Admission,'Yes');
icuLOS  = T.ICU_LOS_days;                 % blank (NaN) when no ICU stay
hospLOS = T.Hospital_LOS_days;
escYes  = strcmp(T.Escalation_Required,'Yes');
hyp     = strcmp(T.Hyponatremia,'Yes');
hypN    = strcmp(T.Hyponatremia,'No');

%% 2. MANUSCRIPT NUMBERS (descriptive) ------------------------------------
fprintf('=================================================================\n');
fprintf('  MANUSCRIPT NUMBERS  (N=%d)\n', N);
fprintf('=================================================================\n\n');

%% A. Cohort, demographics, hospital course
fprintf('--- A. Cohort, demographics, hospital course ---\n');
fprintf('  Age (years)                     : %s\n', mir(T.Age_years));
fprintf('  Female                          : %s\n', npct(sum(strcmp(T.Sex,'F')), N));
fprintf('  Weight (kg)                     : %s\n', mir(T.Weight_kg));
printCats('Setting of SE onset', T.Setting_SE_Onset, {'Prior_to_arrival','ICU','ED','Floor'}, N);
fprintf('  Day of SE onset from admission  : %s\n', mir(T.Day_SE_Onset_from_Admission));
fprintf('  ICU at some point               : %s\n', npct(sum(icuPt), N));
fprintf('  Hospital LOS (days)             : %s\n', mir(hospLOS));
fprintf('  ICU LOS (days), ICU pts only    : %s\n', mir(icuLOS(icuPt)));
fprintf('  Hospital LOS, survivors only    : %s\n', mir(hospLOS(~dead)));
fprintf('\n');

%% B. Semiology, etiology, ASMs, OXC administration
fprintf('--- B. Semiology, etiology, ASMs, OXC administration ---\n');
printCats('Seizure semiology', T.Seizure_Type, {'Focal_Motor','Focal_Non-motor','Focal_to_Bilateral'}, N);
printCats('Etiology category', T.Etiology_Category, {'Structural','Metabolic','Infectious'}, N);
fprintf('  Prior ASMs (count)              : %s\n', mir(T.Prior_ASM_Count));
fprintf('  Concomitant ASMs incl. anesthetics (count): %s\n', mir(T.Concomitant_ASM_Count));
fprintf('  Patients at the 4-agent recording limit   : %d (%s)\n', sum(T.Concomitant_ASM_Count >= 4), idList(T.Concomitant_ASM_Count >= 4, PID));
agents = {};
for i = 1:N
    if ~strcmp(T.Concomitant_Agents{i}, 'None')
        agents = [agents, strsplit(T.Concomitant_Agents{i}, '; ')]; %#ok<AGROW>
    end
end
agents = agents(:);
[ua,~,ic] = unique(agents);  cnt = accumarray(ic,1);
[cnt,ord] = sort(cnt,'descend');  ua = ua(ord);
fprintf('  Concomitant agents (patients)   : ');
for k = 1:numel(ua), fprintf('%s %d; ', ua{k}, cnt(k)); end
fprintf('\n');
anesPt = strcmp(T.Concomitant_Anesthetic,'Yes');
fprintf('  Patients with an anesthetic     : %d (%s) | propofol %d, ketamine %d, midazolam %d\n', sum(anesPt), idList(anesPt,PID), ...
    sum(strcmp(agents,'Propofol')), sum(strcmp(agents,'Ketamine')), sum(strcmp(agents,'Midazolam')));
fprintf('  Benzodiazepine before OXC       : %s\n', npct(sum(strcmp(T.Benzo_Before_OXC,'Yes')), N));
printCats('OXC started in', T.OXC_Setting, {'ICU','Floor','Step_Down'}, N);
fprintf('  Total OXC load (mg)             : %s\n', mir(T.OXC_Total_Load_mg));
fprintf('  Total OXC load (mg/kg)          : %s\n', mir(T.OXC_Load_mg_per_kg));
fprintf('  Day of OXC from admission       : %s\n', mir(T.Day_OXC_from_Admission));
fprintf('  SE onset to OXC (days)          : %s\n', mir(T.Days_SE_Onset_to_OXC));
nAdm = T.OXC_Load_Administrations;
fprintf('  Load administrations            : 1 x %d, 2 x %d, 3 x %d, 4 x %d  (single administration: %s)\n', ...
    sum(nAdm==1), sum(nAdm==2), sum(nAdm==3), sum(nAdm==4), idList(nAdm==1, PID));
mStarted = strcmp(T.OXC_Maintenance_Started,'Yes');
fprintf('  Maintenance started             : %s  (not started: %s)\n', npct(sum(mStarted),N), idList(~mStarted, PID));
fprintf('  Maintenance dose (mg/day)       : %s\n', mir(T.OXC_Maintenance_mg_per_day(mStarted)));
fprintf('\n');

%% C. Efficacy
fprintf('--- C. Efficacy ---\n');
fprintf('  Responder          : %s\n', cpStr(sum(isR),  N));
fprintf('  Partial responder  : %s\n', cpStr(sum(isP),  N));
fprintf('  Non-responder      : %s\n', cpStr(sum(isNR), N));
fprintf('    Partial responders: seizures stopped (with escalation) = %d; reduced but not stopped = %d\n', ...
    sum(isP & isCess), sum(isP & isPart));
fprintf('  First dose Full    : %s\n', cpStr(sum(strcmp(T.First_Dose_Response,'Full')),    N));
fprintf('  First dose Partial : %s\n', cpStr(sum(strcmp(T.First_Dose_Response,'Partial')), N));
fprintf('  First dose None    : %s\n', cpStr(sum(strcmp(T.First_Dose_Response,'None')),    N));
fprintf('  Any first-dose benefit (Full or Partial): %s\n', cpStr(sum(~strcmp(T.First_Dose_Response,'None')), N));
fprintf('  Further ASM escalation required: %s\n', cpStr(sum(escYes), N));
fprintf('  Responders        : %s\n  Partial responders: %s\n  Non-responders    : %s\n', ...
    idList(isR,PID), idList(isP,PID), idList(isNR,PID));
escNames = {'Levetiracetam','Midazolam','Lacosamide','Clobazam','Zonisamide','Topiramate', ...
    'Clonazepam','Valproate','Fosphenytoin','Lorazepam','Magnesium'};
fprintf('  Escalation agents among the %d patients with escalation: ', sum(escYes));
for k = 1:numel(escNames)
    hit = escYes & cellfun(@(s) hasAgent(s, escNames{k}), T.Escalation_Agents);
    fprintf('%s %d; ', escNames{k}, sum(hit));
end
fprintf('\n');
fprintf('  Non-responders (semiology): ');
idx = find(isNR);
for k = 1:numel(idx), fprintf('%s %s; ', PID{idx(k)}, T.Seizure_Type{idx(k)}); end
fprintf('\n\n');

%% D. Safety: hyponatremia
fprintf('--- D. Hyponatremia ---\n');
pre   = strcmp(T.Baseline_Na_Low,'Yes');
newOn = strcmp(T.New_Onset_Hyponatremia,'Yes');
fprintf('  Hyponatremia (below 135, any time): %s\n', cpStr(sum(hyp), N));
fprintf('  Severity among the %d with hyponatremia: mild %d, moderate %d, severe %d\n', sum(hyp), ...
    sum(hyp & strcmp(T.Hyponatremia_Severity,'Mild')), sum(hyp & strcmp(T.Hyponatremia_Severity,'Moderate')), ...
    sum(hyp & strcmp(T.Hyponatremia_Severity,'Severe')));
fprintf('  Pre-existing low sodium (baseline below 135): n=%d (%s)\n', sum(pre), idList(pre,PID));
fprintf('  New-onset hyponatremia (normal baseline)    : %s\n', cpStr(sum(newOn), sum(~pre)));
fprintf('    Severity among the %d new-onset: mild %d, moderate %d, severe %d\n', sum(newOn), ...
    sum(newOn & strcmp(T.Hyponatremia_Severity,'Mild')), sum(newOn & strcmp(T.Hyponatremia_Severity,'Moderate')), ...
    sum(newOn & strcmp(T.Hyponatremia_Severity,'Severe')));
fprintf('  Baseline sodium                 : %s\n', mir(T.Na_Baseline_mEqL));
fprintf('  Sodium at 24 h                  : %s\n', mir(T.Na_24h_mEqL));
fprintf('  Sodium at 48 h                  : %s\n', mir(T.Na_48h_mEqL));
fprintf('  Lowest sodium                   : %s\n', mir(T.Na_Lowest_mEqL));
dNa = T.Na_Decrease_mEqL;
fprintf('  Decrease from baseline          : %s\n', mir(dNa));
fprintf('  Decrease >= 5 mEq/L             : %s\n', npct(sum(dNa >= 5),  N));
fprintf('  Decrease >= 10 mEq/L            : %s\n', npct(sum(dNa >= 10), N));
d = T.Na_Lowest_day;
fprintf('  Day of lowest sodium, all %d with hyponatremia: %s\n', sum(hyp), mir(d(hyp)));
fprintf('  Day of lowest sodium, %d new-onset            : %s\n', sum(newOn), mir(d(newOn)));
fprintf('  Day of lowest sodium (all hyponatremia): <=2 d n=%d (%s); 3-7 d n=%d (%s); >7 d n=%d (%s)\n', ...
    sum(hyp & d<=2), idList(hyp & d<=2,PID), sum(hyp & d>=3 & d<=7), idList(hyp & d>=3 & d<=7,PID), ...
    sum(hyp & d>7), idList(hyp & d>7,PID));
fprintf('  Sodium below 135 at 24 h: n=%d (%s); at 48 h: n=%d (%s)\n', ...
    sum(T.Na_24h_mEqL<135), idList(T.Na_24h_mEqL<135,PID), sum(T.Na_48h_mEqL<135), idList(T.Na_48h_mEqL<135,PID));
for lbl = {'TBI','SAH'}
    m = strcmp(T.SAH_TBI, lbl{1});
    fprintf('  %s: %d patients overall, %d with hyponatremia\n', lbl{1}, sum(m), sum(m & hyp));
end
fprintf('\n');

%% E. Discharge outcomes
fprintf('--- E. Discharge outcomes ---\n');
printCats('Discharge disposition', T.Discharge_Disposition, ...
    {'Home','Nursing_Home','Inpatient_Rehab','Hospice','LTACH','Expired'}, N);
fprintf('  In-hospital death               : %s\n', cpStr(sum(dead), N));
fprintf('  Deceased: age %s; male n=%d; structural etiology n=%d\n', mir(T.Age_years(dead)), ...
    sum(dead & strcmp(T.Sex,'M')), sum(dead & strcmp(T.Etiology_Category,'Structural')));
fprintf('  Deceased by efficacy: responder %d, partial responder %d, non-responder %d\n', ...
    sum(dead & isR), sum(dead & isP), sum(dead & isNR));
onOXC = strcmp(T.Discharged_on_OXC,'Yes');
fprintf('  Discharged on OXC (all patients): %s\n', cpStr(sum(onOXC), N));
fprintf('  Discharged on OXC among the %d discharged alive: %d  (not on OXC: %s)\n', ...
    sum(~dead), sum(onOXC & ~dead), idList(~dead & ~onOXC, PID));
fprintf('\n');

%% 3. EXPLORATORY ANALYSES ------------------------------------------------
fprintf('=================================================================\n');
fprintf('  EXPLORATORY ANALYSES  (N=%d)\n', N);
fprintf('  Categorical associations: Fisher-Freeman-Halton exact test.\n');
fprintf('  Contingency tables are exported to %s\n', XLSX_CONT);
fprintf('=================================================================\n\n');

%% 3.1 Seizure type x efficacy
fprintf('--- Seizure type vs efficacy ---\n');
stCats = {'Focal_Motor','Focal_Non-motor','Focal_to_Bilateral'};
stLbl  = {'Focal Motor','Focal Non-Motor','Focal->Bilateral TC'};
contMat = countTable(T.Seizure_Type, stCats, ov, effCats);
contTableOut('S1_SeizureType_Efficacy','Seizure type (rows) x overall efficacy (columns)', stLbl, respLbl, contMat, XLSX_CONT);

%% 3.2 Etiology x efficacy
fprintf('--- Etiology category vs efficacy ---\n');
eCats = {'Structural','Metabolic','Infectious'};
contMat = countTable(T.Etiology_Category, eCats, ov, effCats);
contTableOut('S2_Etiology_Efficacy','Etiology category (rows) x overall efficacy (columns)', eCats, respLbl, contMat, XLSX_CONT);

%% 3.3 First-dose response x efficacy (concordance, not a predictor)
fprintf('--- First-dose response vs efficacy (concordance; overlaps with the final class) ---\n');
fdCats = {'Full','Partial','None'};
contMat = countTable(T.First_Dose_Response, fdCats, ov, effCats);
contTableOut('S3_FirstDose_Efficacy','First-dose response (rows) x overall efficacy (columns)', fdCats, respLbl, contMat, XLSX_CONT);

%% 3.4 Setting of SE onset x efficacy
fprintf('--- Setting of SE onset vs efficacy ---\n');
onsetCats = {'Prior_to_arrival','ED','ICU','Floor'};
contMat = countTable(T.Setting_SE_Onset, onsetCats, ov, effCats);
contTableOut('S4_Setting4_Efficacy','Setting of SE onset (rows) x overall efficacy (columns)', onsetCats, respLbl, contMat, XLSX_CONT);

fprintf('--- Setting of SE onset (prior to arrival vs in-hospital) vs efficacy ---\n');
contMat = countTable(T.SE_Onset_Prior_to_Arrival, {'Yes','No'}, ov, effCats);
contTableOut('S5_Setting2_Efficacy','Setting of SE onset, prior to arrival vs in-hospital (rows) x overall efficacy (columns)', ...
    {'Prior to Arrival','In-Hospital'}, respLbl, contMat, XLSX_CONT);

%% 3.5 Etiology x hyponatremia
fprintf('--- Etiology category vs hyponatremia ---\n');
contMat = countTable(T.Etiology_Category, eCats, T.Hyponatremia, {'Yes','No'});
contTableOut('S6_Etiology_Hyponatremia','Etiology category (rows) x hyponatremia (columns)', eCats, {'Hyponatremia Yes','Hyponatremia No'}, contMat, XLSX_CONT);

%% 3.6 OPTIONAL: concomitant anesthetic x efficacy (attribution; not in the main analysis)
fprintf('--- OPTIONAL: concomitant anesthetic vs efficacy ---\n');
contMat = countTable(T.Concomitant_Anesthetic, {'Yes','No'}, ov, effCats);
contTableOut('Optional_Anesthetic_Efficacy','Concomitant anesthetic (rows) x overall efficacy (columns)', ...
    {'Anesthetic present','No anesthetic'}, respLbl, contMat, XLSX_CONT);

%% 3.7 Length of stay by efficacy group (Kruskal-Wallis)
fprintf('--- Hospital LOS vs efficacy ---\n');
grpData = cell(1,3);
for k = 1:3
    vals = hospLOS(strcmp(ov, effCats{k}));
    grpData{k} = vals(~isnan(vals));
    fprintf('  %-18s %s\n', effLabels{k}, mir(grpData{k}));
end
kwReport(grpData, effLabels);

fprintf('--- ICU LOS vs efficacy (ICU patients only) ---\n');
grpData = cell(1,3);
for k = 1:3
    vals = icuLOS(strcmp(ov, effCats{k}));
    grpData{k} = vals(~isnan(vals) & vals > 0);
    fprintf('  %-18s %s\n', effLabels{k}, mir(grpData{k}));
end
kwReport(grpData, effLabels);
fprintf('  Note: LOS is confounded by in-hospital death (%d/%d), severity, etiology and exposure time.\n\n', sum(dead), N);

%% 3.8 Loading dose and LOS vs hyponatremia (Wilcoxon rank-sum)
fprintf('--- Loading dose (mg/kg) vs hyponatremia ---\n');
doseY = T.OXC_Load_mg_per_kg(hyp);   doseN = T.OXC_Load_mg_per_kg(hypN);
fprintf('  Hyponatremia Yes: %s\n', mir(doseY));
fprintf('  Hyponatremia No : %s\n', mir(doseN));
rankSumReport(doseY, doseN);

fprintf('--- Hospital LOS vs hyponatremia ---\n');
losY = hospLOS(hyp);   losN = hospLOS(hypN);
fprintf('  Hyponatremia Yes: %s\n', mir(losY));
fprintf('  Hyponatremia No : %s\n', mir(losN));
rankSumReport(losY, losN);

fprintf('Contingency tables written to: %s\n\n', XLSX_CONT);

%% 4. FIGURES -------------------------------------------------------------
fprintf('=================================================================\n');
fprintf('  FIGURES\n');
fprintf('=================================================================\n');

%% Figure 1A: length of stay (hospital + ICU)
fprintf('--- Figure 1A: Length of stay ---\n');
f1a = newFig('');
hlos   = hospLOS(~isnan(hospLOS));
iculos = icuLOS(~isnan(icuLOS) & icuLOS > 0);
allVals = [hlos(:); iculos(:)];
allGrp  = [repmat({'Hospital LOS'}, numel(hlos), 1); repmat({'ICU LOS'}, numel(iculos), 1)];
catGrp  = categorical(allGrp, {'Hospital LOS','ICU LOS'});
bc = boxchart(allVals, 'GroupByColor', catGrp);
bc(1).BoxFaceColor = PALETTE(1,:);  bc(1).MarkerColor = PALETTE(1,:);
bc(1).BoxWidth = .75;
bc(2).BoxWidth = .75;
ax = gca;
ax.Box = 'off'; ax.YGrid = 'on'; ax.GridAlpha = 0.3;
ax.XTick = [];
ax.FontSize = 20;
f1a.Position = [50 50 400 550];
print(fullfile(FIGDIR,'Fig1A_LengthOfStay.png'),'-dpng','-r300')

%% Figure 1B: OXC loading dose (mg/kg)
fprintf('--- Figure 1B: OXC loading dose mg/kg ---\n');
f1b = newFig('');
ax = axes('Parent', f1b);
mgkg = T.OXC_Load_mg_per_kg(~isnan(T.OXC_Load_mg_per_kg));
histogram(ax, mgkg, 'BinWidth',3, 'FaceColor',PALETTE(4,:), 'EdgeColor','w','LineWidth',1);
xlabel(ax,'Loading Dose (mg/kg)'); ylabel(ax,'Count');
hxl = xline(ax, median(mgkg),'--k','LineWidth',1.5, ...
    'Label', sprintf('Median = %.1f mg/kg', median(mgkg)), ...
    'LabelHorizontalAlignment','right');
hxl.FontSize = 16;
ax.Box = 'off'; ax.YGrid = 'on'; ax.GridAlpha = 0.3;
ax.FontSize = 20;
print(fullfile(FIGDIR,'Fig1B_OXC_LoadDose_mgkg.png'),'-dpng','-r300')

%% Figure 2A: efficacy summary
% Three 100%-stacked horizontal bars (top to bottom):
%   overall efficacy (Responder / Partial / Non-responder)
%   first-dose response (Full / Partial / None; same colours as overall efficacy)
%   further ASM escalation needed (No = red on the left, Yes = green on the right)
fprintf('--- Figure 2A: Efficacy summary ---\n');
ovCnts  = cellfun(@(s) sum(strcmp(ov, s)), effCats);
fdCnts  = cellfun(@(s) sum(strcmp(T.First_Dose_Response, s)), {'Full','Partial','None'});
escCnts = [sum(~escYes), 0, sum(escYes)];      % No on the left, Yes on the right
allRows = [escCnts; fdCnts; ovCnts] ./ N * 100;      % barh draws row 1 at the bottom
fprintf('  Further escalation     : %s\n', sprintf('%5.1f%% ', allRows(1,:)));
fprintf('  First-dose response    : %s\n', sprintf('%5.1f%% ', allRows(2,:)));
fprintf('  Overall efficacy       : %s\n', sprintf('%5.1f%% ', allRows(3,:)));

newFig('');
hbar = barh(allRows, 'stacked');
hbar(1).BarWidth = 0.6;
grid on;
hbar(1).FaceColor='flat'; hbar(1).CData = [PALETTE(3,:); PALETTE(9,:);  PALETTE(9,:)];
hbar(2).FaceColor='flat'; hbar(2).CData = [PALETTE(8,:); PALETTE(10,:); PALETTE(10,:)];
hbar(3).FaceColor='flat'; hbar(3).CData = [PALETTE(8,:); PALETTE(11,:); PALETTE(11,:)];
ax = gca;
xlim(ax, [0 100]);
ylim(ax, [0.4 3.6]);
ax.Box = 'off';
ax.YGrid = 'off';
ax.XGrid = 'on';
ax.GridAlpha = 0.25;
ax.XTick = [];
ax.YTick = [];
ax.FontSize = 20;
print(fullfile(FIGDIR,'Fig2A_EfficacySummary.png'),'-dpng','-r300')

%% Figure 2B: LOS by efficacy group
fprintf('--- Figure 2B: LOS by efficacy group ---\n');
newFig('');
grpLabels = {'Responder','Partial Responder','Non-Responder'};

ax = subplot(1,2,1);                                   % hospital LOS
losData = {}; losGrp = {};
for k = 1:3
    mask = strcmp(ov, effCats{k});
    vals = hospLOS(mask);
    vals = vals(~isnan(vals));
    if ~isempty(vals), losData{end+1} = vals; end %#ok<SAGROW>
    losGrp = [losGrp; repmat(grpLabels(k), numel(vals), 1)]; %#ok<AGROW>
end
allVals = vertcat(losData{:});
catGrp  = categorical(losGrp, grpLabels);
boxchart(ax, catGrp, allVals(:), 'GroupByColor',catGrp,'BoxWidth',2.7,'BoxFaceAlpha',0.7);
colororder(PALETTE(9:11,:))
ax.Box = 'off'; ax.YGrid = 'on';
ax.FontSize = 20;
ax.XTick = [];

ax = subplot(1,2,2);                                   % ICU LOS (ICU patients only)
losData2 = {}; losGrp2 = {};
for k = 1:3
    mask = strcmp(ov, effCats{k});
    vals = icuLOS(mask);
    vals = vals(~isnan(vals) & vals > 0);
    if ~isempty(vals), losData2{end+1} = vals; end %#ok<SAGROW>
    losGrp2 = [losGrp2; repmat(grpLabels(k), numel(vals), 1)]; %#ok<AGROW>
end
allVals2 = vertcat(losData2{:});
catGrp2  = categorical(losGrp2, grpLabels);
boxchart(ax, catGrp2, allVals2(:), 'GroupByColor',catGrp2,'BoxWidth',2.7,'BoxFaceAlpha',0.7);
colororder(PALETTE(9:11,:))
ax.Box = 'off'; ax.YGrid = 'on';
ax.FontSize = 20;
ax.XTick = [];
print(fullfile(FIGDIR,'Fig2B_LOS_byEfficacy.png'),'-dpng','-r300')

%% Figure 3: sodium trajectory
fprintf('--- Figure 3: Sodium trajectory ---\n');
f3 = newFig('');
ax = axes('Parent', f3);
naVars   = {'Na_Baseline_mEqL','Na_24h_mEqL','Na_48h_mEqL','Na_Lowest_mEqL'};
naLabels = {'Baseline','24h','48h','Lowest'};
naData = []; naGroup = {};
for k = 1:numel(naVars)
    vals = T.(naVars{k});
    vals = vals(~isnan(vals));
    naData  = [naData;  vals(:)]; %#ok<AGROW>
    naGroup = [naGroup; repmat(naLabels(k), numel(vals), 1)]; %#ok<AGROW>
end
boxchart(ax, categorical(naGroup, naLabels), naData, ...
    'BoxFaceColor',PALETTE(1,:),'MarkerColor',PALETTE(1,:));
yline(ax, 135, '--r', 'LineWidth',1.5);                                   % 135 mEq/L
yline(ax, 145, '--', 'Color',[0.5 0.5 0.5], 'LineWidth',1.5);             % 145 mEq/L
ylabel(ax,'Sodium (mEq/L)');
ax.Box = 'off'; ax.YGrid = 'on'; ax.GridAlpha = 0.3;
ax.FontSize = 20;
print(fullfile(FIGDIR,'Fig3_SodiumTrajectory.png'),'-dpng','-r300')

%% Supplementary Figure 1: prior and concomitant agents
fprintf('--- Supplementary Figure 1: prior ASMs and concomitant agents ---\n');
figure('Color',[0.97 0.97 0.98],'Position',[0 0 700 500]);

ax4 = subplot(1,2,1);                                  % A: prior ASM count
pc = T.Prior_ASM_Count(~isnan(T.Prior_ASM_Count));
histogram(ax4, pc, 'BinEdges',-0.5:1:max(pc)+0.5, 'FaceColor',PALETTE(2,:), ...
    'EdgeColor','w','LineWidth',1);
ax4.XTick = 0:max(pc);
ax4.Box = 'off'; ax4.YGrid = 'on'; ax4.GridAlpha = 0.3;
ax4.FontSize = 20;

ax6 = subplot(1,2,2);                                  % B: concomitant agents incl. anesthetics
cc = T.Concomitant_ASM_Count;
histogram(ax6, cc, 'BinEdges',-0.5:1:max(cc)+0.5, 'FaceColor',PALETTE(5,:), ...
    'EdgeColor','w','LineWidth',1);
ax6.XTick = 0:max(cc);
ax6.Box = 'off'; ax6.YGrid = 'on'; ax6.GridAlpha = 0.3;
ax6.FontSize = 20;
print(fullfile(FIGDIR,'FigS1_Prior-ASMs.png'),'-dpng','-r300')

%% THE END
fprintf('=================================================================\n');
fprintf('Figures saved to: %s\n', FIGDIR);
fprintf('Tables saved to : %s\n', TBLDIR);
fprintf('Analysis complete.\n');

%% ========================================================================
%  LOCAL FUNCTIONS
%% ========================================================================

function f = newFig(titleStr)
f = figure('Color',[0.97 0.97 0.98],'Position',[0 0 500 500]);
sgtitle(titleStr,'FontSize',13,'FontWeight','bold','FontName','Arial');
end

function s = numStr(v)
% Compact number formatting (27.75 -> '27.75', 2400 -> '2400')
s = sprintf('%.4g', v);
end

function s = mir(x)
% 'n=22  median 19 (IQR 10-25; range 4-51)'. IQR = prctile (MATLAB default, Hazen).
x = x(:);  x = x(~isnan(x));
if isempty(x), s = 'n=0'; return; end
q = prctile(x, [25 75]);
s = sprintf('n=%d  median %s (IQR %s-%s; range %s-%s)', numel(x), numStr(median(x)), ...
    numStr(q(1)), numStr(q(2)), numStr(min(x)), numStr(max(x)));
end

function s = npct(k, n)
s = sprintf('%d (%.1f%%)', k, 100*k/n);
end

function s = cpStr(k, n)
% k/n with a Clopper-Pearson (exact) 95% CI
[~, ci] = binofit(k, n);
s = sprintf('%d/%d = %.1f%% (95%% CI %.1f-%.1f%%)', k, n, 100*k/n, 100*ci(1), 100*ci(2));
end

function s = pStr(p)
if p < 0.0001, s = '<0.0001'; else, s = sprintf('%.4f', p); end
end

function s = idList(mask, pid)
% Comma-separated patient codes for the logical mask
mask = logical(mask(:));
if ~any(mask), s = 'none'; else, s = strjoin(pid(mask)', ', '); end
end

function tf = hasAgent(listStr, name)
% true if the "; "-separated agent list contains the generic name
tf = any(strcmp(strsplit(listStr, '; '), name));
end

function printCats(label, col, cats, N)
% n (%) for each listed category of a text column
fprintf('  %s: ', label);
tot = 0;
for k = 1:numel(cats)
    n = sum(strcmp(col, cats{k}));
    tot = tot + n;
    if n > 0, fprintf('%s %d (%.1f%%); ', cats{k}, n, 100*n/N); end
end
if tot < N, fprintf('[other/unlisted: %d]', N - tot); end
fprintf('\n');
end

function reportCheck(msg, flagMask, pid)
% One line per data check: OK, or WARN with the patients concerned
flagMask = logical(flagMask(:));
if any(flagMask)
    fprintf('  [WARN] %s: %s\n', msg, strjoin(pid(flagMask)', ', '));
else
    fprintf('  [ OK ] %s\n', msg);
end
end

function kwReport(grpData, labels)
% Kruskal-Wallis across the efficacy groups
g = {};  v = [];
for k = 1:numel(grpData)
    v = [v; grpData{k}(:)]; %#ok<AGROW>
    g = [g; repmat(labels(k), numel(grpData{k}), 1)]; %#ok<AGROW>
end
[p, tbl] = kruskalwallis(v, g, 'off');
fprintf('  Kruskal-Wallis H = %.3f  df = %d  p = %.4f\n', tbl{2,5}, tbl{2,3}, p);
end

function rankSumReport(a, b)
% Wilcoxon rank-sum: MATLAB default plus exact and approximate p-values
a = a(~isnan(a));  b = b(~isnan(b));
if numel(a) < 2 || numel(b) < 2
    fprintf('  Insufficient data for Wilcoxon rank-sum.\n\n'); return
end
p_def = ranksum(a, b);
try, p_ex = ranksum(a, b, 'method', 'exact');       catch, p_ex = NaN; end
try, p_ap = ranksum(a, b, 'method', 'approximate'); catch, p_ap = NaN; end
fprintf('  Wilcoxon rank-sum p = %.4f (default) | exact p = %.4f | approximate p = %.4f\n\n', p_def, p_ex, p_ap);
end

function M = countTable(rowVar, rowCats, colVar, colCats)
% Count matrix: rows = categories of rowVar, columns = categories of colVar
M = zeros(numel(rowCats), numel(colCats));
for i = 1:numel(rowCats)
    mi = strcmp(rowVar, rowCats{i});
    for j = 1:numel(colCats)
        M(i,j) = sum(mi & strcmp(colVar, colCats{j}));
    end
end
end

function [chi2stat, df, expected] = chi2table(ctable)
% Chi-square statistic and expected counts; used ONLY to report the share of
% expected cells below 5 (the reason exact tests are used). No chi-square
% p-value is reported.
observed = double(ctable);
rowSums  = sum(observed, 2);
colSums  = sum(observed, 1);
total    = sum(rowSums);
expected = rowSums * colSums / total;
df       = (size(observed,1)-1) * (size(observed,2)-1);
chi2stat = sum(sum((observed - expected).^2 ./ max(expected, 1e-10)));
end

function p = contTableOut(sheetName, tblTitle, rowLbl, colLbl, mat, xlsxFile)
% Print a contingency table with its exact p-value and export it (supplement).
mat = double(mat);
keep = sum(mat,2) > 0;                 % drop empty rows
mat = mat(keep,:);  rowLbl = rowLbl(keep);
[p, nTab] = ffhExact(mat);
[~,~,expMat] = chi2table(mat);
pctSmall = mean(expMat(:) < 5) * 100;

nr = size(mat,1);  nc = size(mat,2);
fprintf('  %s\n', tblTitle);
hdr = sprintf('  %-24s', '');
for j = 1:nc, hdr = [hdr sprintf('%19s', colLbl{j})]; end %#ok<AGROW>
fprintf('%s%10s\n', hdr, 'Total');
for i = 1:nr
    ln = sprintf('  %-24s', rowLbl{i});
    for j = 1:nc, ln = [ln sprintf('%19d', mat(i,j))]; end %#ok<AGROW>
    fprintf('%s%10d\n', ln, sum(mat(i,:)));
end
ln = sprintf('  %-24s', 'Total');
for j = 1:nc, ln = [ln sprintf('%19d', sum(mat(:,j)))]; end
fprintf('%s%10d\n', ln, sum(mat(:)));
fprintf('  Fisher-Freeman-Halton exact p = %s  (%d tables enumerated; %.0f%% of expected cells < 5)\n\n', ...
    pStr(p), nTab, pctSmall);

if ~isempty(xlsxFile)
    out = cell(nr+4, nc+2);
    out{1,1} = tblTitle;
    for j = 1:nc, out{2,j+1} = colLbl{j}; end
    out{2,nc+2} = 'Total';
    for i = 1:nr
        out{i+2,1} = rowLbl{i};
        for j = 1:nc, out{i+2,j+1} = mat(i,j); end
        out{i+2,nc+2} = sum(mat(i,:));
    end
    out{nr+3,1} = 'Total';
    for j = 1:nc, out{nr+3,j+1} = sum(mat(:,j)); end
    out{nr+3,nc+2} = sum(mat(:));
    out{nr+4,1} = sprintf('Fisher-Freeman-Halton exact p = %s; %.0f%% of expected cells < 5', pStr(p), pctSmall);
    writecell(out, xlsxFile, 'Sheet', sheetName, 'WriteMode', 'overwritesheet');
end
end

function [p, nTables] = ffhExact(tab)
% Fisher-Freeman-Halton exact test for an r x c table (probability ordering).
% Full enumeration of all tables with the observed margins; for a 2x2 table
% this equals Fisher's exact test (two-sided). Suitable for small N only.
tab = double(tab);
tab = tab(sum(tab,2) > 0, sum(tab,1) > 0);
[nr, nc] = size(tab);
if nr < 2 || nc < 2, p = 1; nTables = 1; return; end
R = sum(tab,2)';  C = sum(tab,1);  Ntot = sum(R);
const = sum(gammaln(R+1)) + sum(gammaln(C+1)) - gammaln(Ntot+1);
obs   = const - sum(gammaln(tab(:)+1));          % log-probability of the observed table
st.p = 0;  st.n = 0;
st = enumRows(1, C, R, nr, 0, const, obs, st);
p = min(1, st.p);  nTables = st.n;
end

function st = enumRows(i, colRem, R, nr, accLog, const, obs, st)
% Recursively fill rows 1..nr-1; the last row is fixed by the remaining column totals.
if i == nr
    if sum(colRem) ~= R(i), return; end
    lg = const - (accLog + sum(gammaln(colRem+1)));
    st.n = st.n + 1;
    if lg <= obs + 1e-9, st.p = st.p + exp(lg); end
    return
end
comps = compositions(R(i), colRem);
for k = 1:size(comps,1)
    x = comps(k,:);
    st = enumRows(i+1, colRem - x, R, nr, accLog + sum(gammaln(x+1)), const, obs, st);
end
end

function M = compositions(total, caps)
% All non-negative integer vectors x with sum(x) = total and x <= caps
nc = numel(caps);
if nc == 1
    if total <= caps(1), M = total; else, M = zeros(0,1); end
    return
end
M = zeros(0, nc);
for x1 = 0:min(total, caps(1))
    sub = compositions(total - x1, caps(2:end));
    if ~isempty(sub), M = [M; repmat(x1, size(sub,1), 1), sub]; end %#ok<AGROW>
end
end
