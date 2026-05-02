/* ========================================= */
/* 1. Understand the Data                    */
/* ========================================= */

proc import datafile="/home/u64504915/healthcare-dataset-stroke-data.csv"
    out=stroke_data
    dbms=csv
    replace;
    guessingrows=max;
run;

proc print data=stroke_data (obs=10);
    title "Preview of Dataset";
run;

proc contents data=stroke_data;
    title "Dataset Structure and Variable Types";
run;

proc means data=stroke_data n mean std min max;
    var age avg_glucose_level bmi;
    title "Basic Statistics for Numerical Variables";
run;

proc freq data=stroke_data;
    tables stroke;
    title "Distribution of Target Variable (Stroke)";
run;

/* ========================================= */
/* 2. Investigate the Data                   */
/* ========================================= */

proc means data=stroke_data n nmiss mean median std min max;
    var age avg_glucose_level bmi;
    title "Summary Statistics for Numerical Variables";
run;

proc freq data=stroke_data;
    tables gender smoking_status work_type stroke / nocum;
    title "Categorical Variables Distribution";
run;

proc freq data=stroke_data;
    tables stroke;
    title "Stroke Distribution";
run;

proc sgplot data=stroke_data;
    vbar stroke / group=gender groupdisplay=cluster;
    title "Stroke Occurrence by Gender";
run;

proc sgplot data=stroke_data;
    hbox age / category=stroke;
    title "Age Distribution by Stroke";
run;

proc sgplot data=stroke_data;
    vbox avg_glucose_level / category=stroke;
    title "Glucose Level vs Stroke";
run;

proc sgplot data=stroke_data;
    vbox bmi / category=stroke;
    title "BMI vs Stroke";
run;

proc freq data=stroke_data;
    tables (hypertension heart_disease)*stroke / chisq nocol nopercent;
    title "Association Between Health Conditions and Stroke";
run;

proc corr data=stroke_data;
    var age avg_glucose_level bmi stroke;
    title "Correlation Matrix";
run;

proc sgrender template=Stat.Corr.Graphics.ScatterPlotMatrix data=stroke_data;
    title "Scatter Plot Matrix";
run;

/* ========================================= */
/* 3. Train-Test Split                       */
/* ========================================= */

proc surveyselect data=stroke_data
    out=split_data
    samprate=0.8
    seed=123
    outall;
run;

data train_raw test_raw;
    set split_data;
    if selected then output train_raw;
    else output test_raw;
run;

/* ========================================= */
/* 4. Fix the Data (TRAIN)                   */
/* ========================================= */

data train_fixed;
    set train_raw;

    bmi_num = input(bmi, best12.);
    drop bmi;
    rename bmi_num = bmi;
run;

proc means data=train_fixed noprint;
    var bmi;
    output out=train_mean_bmi mean=avg_bmi;
run;

data train_clean;
    if _n_ = 1 then set train_mean_bmi;
    set train_fixed;

    if bmi = . then bmi = avg_bmi;

    if smoking_status = "Unknown" then smoking_status = "never smoked";

    if gender = "Male" then gender_n = 1;
    else gender_n = 0;

    if ever_married = "Yes" then married_n = 1;
    else married_n = 0;

    drop id avg_bmi _freq_ _type_;
run;

proc print data=train_clean (obs=10);
    title "Preview of Cleaned Train Data";
run;

proc means data=train_clean n nmiss;
    var bmi;
    title "Missing Values Check After Cleaning (Train)";
run;

proc sgplot data=train_clean;
    vbox bmi;
    title "BMI Distribution After Cleaning (Train)";
run;

/* ========================================= */
/* 5. Apply Same Cleaning to TEST            */
/* ========================================= */

data test_fixed;
    set test_raw;

    bmi_num = input(bmi, best12.);
    drop bmi;
    rename bmi_num = bmi;
run;

data test_clean;
    if _n_ = 1 then set train_mean_bmi;
    set test_fixed;

    if bmi = . then bmi = avg_bmi;

    if smoking_status = "Unknown" then smoking_status = "never smoked";

    if gender = "Male" then gender_n = 1;
    else gender_n = 0;

    if ever_married = "Yes" then married_n = 1;
    else married_n = 0;

    drop id avg_bmi _freq_ _type_;
run;

/* ========================================= */
/* 6. Outliers (TRAIN)                       */
/* ========================================= */

proc univariate data=train_clean noprint;
    var bmi;
    output out=train_bmi_iqr pctlpts=25 75 pctlpre=Q_;
run;

data train_outliers;
    if _n_ = 1 then set train_bmi_iqr;
    set train_clean;

    IQR_bmi = Q_75 - Q_25;
    lower_bmi = Q_25 - 1.5 * IQR_bmi;
    upper_bmi = Q_75 + 1.5 * IQR_bmi;

    if bmi < lower_bmi then bmi = lower_bmi;
    if bmi > upper_bmi then bmi = upper_bmi;
run;

proc univariate data=train_outliers noprint;
    var avg_glucose_level;
    output out=train_glucose_iqr pctlpts=25 75 pctlpre=Q_;
run;

data train_final;
    if _n_ = 1 then set train_glucose_iqr;
    set train_outliers;

    IQR_glucose = Q_75 - Q_25;
    lower_glucose = Q_25 - 1.5 * IQR_glucose;
    upper_glucose = Q_75 + 1.5 * IQR_glucose;

    if avg_glucose_level < lower_glucose then avg_glucose_level = lower_glucose;
    if avg_glucose_level > upper_glucose then avg_glucose_level = upper_glucose;
run;

/* ========================================= */
/* 7. Apply Outliers to TEST                 */
/* ========================================= */

data test_outliers;
    if _n_ = 1 then set train_bmi_iqr;
    set test_clean;

    IQR_bmi = Q_75 - Q_25;
    lower_bmi = Q_25 - 1.5 * IQR_bmi;
    upper_bmi = Q_75 + 1.5 * IQR_bmi;

    if bmi < lower_bmi then bmi = lower_bmi;
    if bmi > upper_bmi then bmi = upper_bmi;
run;

data test_final;
    if _n_ = 1 then set train_glucose_iqr;
    set test_outliers;

    IQR_glucose = Q_75 - Q_25;
    lower_glucose = Q_25 - 1.5 * IQR_glucose;
    upper_glucose = Q_75 + 1.5 * IQR_glucose;

    if avg_glucose_level < lower_glucose then avg_glucose_level = lower_glucose;
    if avg_glucose_level > upper_glucose then avg_glucose_level = upper_glucose;
run;

/* ========================================= */
/* 8. Feature Engineering                    */
/* ========================================= */

data train_features;
    set train_final;

    if age < 18 then age_group = 'Child';
    else if 18 <= age < 35 then age_group = 'Young Adult';
    else if 35 <= age < 55 then age_group = 'Adult';
    else if 55 <= age < 75 then age_group = 'Senior';
    else age_group = 'Elder';

    if bmi < 18.5 then bmi_category = 'Underweight';
    else if bmi < 25 then bmi_category = 'Normal';
    else if bmi < 30 then bmi_category = 'Overweight';
    else bmi_category = 'Obese';

    high_glucose = (avg_glucose_level > 140);

    if smoking_status = 'smokes' then smoking_n = 2;
    else if smoking_status = 'formerly smoked' then smoking_n = 1;
    else smoking_n = 0;

    risk_score = 0;

    risk_score + (hypertension = 1) * 2;
    risk_score + (heart_disease = 1) * 2;
    risk_score + (high_glucose = 1) * 2;
    risk_score + (bmi_category = 'Overweight') * 1;
    risk_score + (bmi_category = 'Obese') * 2;
    risk_score + (smoking_n > 0) * 1;
    risk_score + (age >= 55) * 2;
run;

data test_features;
    set test_final;

    if age < 18 then age_group = 'Child';
    else if 18 <= age < 35 then age_group = 'Young Adult';
    else if 35 <= age < 55 then age_group = 'Adult';
    else if 55 <= age < 75 then age_group = 'Senior';
    else age_group = 'Elder';

    if bmi < 18.5 then bmi_category = 'Underweight';
    else if bmi < 25 then bmi_category = 'Normal';
    else if bmi < 30 then bmi_category = 'Overweight';
    else bmi_category = 'Obese';

    high_glucose = (avg_glucose_level > 140);

    if smoking_status = 'smokes' then smoking_n = 2;
    else if smoking_status = 'formerly smoked' then smoking_n = 1;
    else smoking_n = 0;

    risk_score = 0;

    risk_score + (hypertension = 1) * 2;
    risk_score + (heart_disease = 1) * 2;
    risk_score + (high_glucose = 1) * 2;
    risk_score + (bmi_category = 'Overweight') * 1;
    risk_score + (bmi_category = 'Obese') * 2;
    risk_score + (smoking_n > 0) * 1;
    risk_score + (age >= 55) * 2;
run;

/* ========================================= */
/* 9. Build and Evaluate Classification Model*/
/* ========================================= */

/* Train Logistic Regression Model on features */
proc logistic data=train_features descending;
    model stroke = age hypertension heart_disease avg_glucose_level bmi gender_n risk_score;
    title "Predictive Model for Stroke - Logistic Regression";
run;

/* Score the test data to get probabilities (P_1) */
proc logistic data=train_features descending;
    model stroke = age hypertension heart_disease avg_glucose_level bmi gender_n risk_score;
    score data=test_features out=pred_results;
run;

/* --- START: Metrics Calculation (Accuracy, Precision, Recall, F1) --- */

data final_metrics_calc;
    set pred_results;
    
    /* Apply 0.1 Threshold for classification as discussed */
    if P_1 > 0.1 then predicted_stroke = 1;
    else predicted_stroke = 0;

    /* Logic for TP, TN, FP, FN */
    if stroke = 1 and predicted_stroke = 1 then TP = 1; else TP = 0;
    if stroke = 0 and predicted_stroke = 0 then TN = 1; else TN = 0;
    if stroke = 0 and predicted_stroke = 1 then FP = 1; else FP = 0;
    if stroke = 1 and predicted_stroke = 0 then FN = 1; else FN = 0;
run;

/* Aggregate the values */
proc means data=final_metrics_calc sum noprint;
    vars TP TN FP FN;
    output out=metrics_summary sum(TP)=TP sum(TN)=TN sum(FP)=FP sum(FN)=FN;
run;

/* Calculate Final Scores */
data model_evaluation_report;
    set metrics_summary;
    Accuracy = (TP + TN) / (TP + TN + FP + FN);
    if (TP + FP) > 0 then Precision = TP / (TP + FP); else Precision = 0;
    if (TP + FN) > 0 then Recall = TP / (TP + FN); else Recall = 0;
    if (Precision + Recall) > 0 then F1_Score = 2 * (Precision * Recall) / (Precision + Recall);
    else F1_Score = 0;
    
    label Accuracy="Overall Accuracy" Precision="Precision" Recall="Recall (Sensitivity)" F1_Score="F1-Score";
    keep Accuracy Precision Recall F1_Score;
run;

/* Print the metrics table directly in the output */
title "Model Performance Metrics - Test Set (Threshold = 0.1)";
proc print data=model_evaluation_report noobs;
run;

/* Display Original Confusion Matrix for reference */
proc freq data=final_metrics_calc;
    tables stroke * predicted_stroke / nopercent norow nocol;
    title "Confusion Matrix for Test Data (Threshold = 0.1)";
run;

/* ========================================= */
/* 10. Visualizations (8 Distinct Charts)    */
/* ========================================= */

/* 1. Age distribution by stroke status */
title "1. Age Distribution by Stroke Status";
proc sgplot data=train_features;
    histogram age / group=stroke transparency=0.5;
    density age / type=kernel group=stroke;
run;

/* 2. BMI categories distribution */
title "2. Stroke Distribution across BMI Categories";
proc sgplot data=train_features;
    vbar bmi_category / group=stroke groupdisplay=cluster;
run;

/* 3. Risk Score impact on stroke */
title "3. Risk Score Impact Analysis";
proc sgplot data=train_features;
    vbox risk_score / category=stroke;
run;

/* 4. Glucose levels distribution */
title "4. Glucose Level Distribution by Stroke Status";
proc sgplot data=train_features;
    vbox avg_glucose_level / category=stroke;
run;

/* 5. Overall Stroke Prevalence */
title "5. Stroke Prevalence Percentage";
proc sgplot data=train_features;
    vbar stroke / stat=percent datalabel fillattrs=(color=ligr);
run;

/* 6. Hypertension impact (Bar Chart) */
title "6. Hypertension Impact on Stroke";
proc sgplot data=train_features;
    vbar hypertension / group=stroke groupdisplay=cluster;
run;

/* 7. Smoking Status Impact */
title "7. Stroke Ratio by Smoking Status";
proc sgplot data=train_features;
    vbar smoking_status / group=stroke stat=percent;
run;

/* 8. Age vs Risk Score Correlation */
title "8. Correlation: Age vs Risk Score";
proc sgplot data=train_features;
    scatter x=age y=risk_score / group=stroke markerattrs=(symbol=circlefilled);
run;
title;
/* ========================================= */
/* 11. Export Final Data                     */
/* ========================================= */

proc export data=train_features
    outfile="/home/u64504915/train_final.csv"
    dbms=csv
    replace;
run;

proc export data=test_features
    outfile="/home/u64504915/test_final.csv"
    dbms=csv
    replace;
run;