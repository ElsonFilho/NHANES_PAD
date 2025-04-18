/*****************************************************************************/
/* NHANES PAD                                                                */
/*****************************************************************************/
/*  National Health and Nutrition Examination Survey (NHANES)                */       
/*  Peripheral Artery Disease (PAD)                                          */
/*  Data collection: household screener, interview, and physical examination.*/
/* OBJECTIVES: 								     */
/*  Understand the survey data and create a predictive model to identify the */
/*  main factors that are related to the disease, to prioritize the physical */
/*  exams and to support the diganostics.                                    */
/* TASKS:                                                                    */
/*  - Start the session;                                                     */
/*  - Data Partition (Training and Validation);                              */
/*  - Feature Engeneering (add additional features);                         */
/*  - Modelling;                                                             */
/*  - Scoring;                                                               */
/*  - Assess.                                                                */ 
/*****************************************************************************/


/*****************************************************************************/
/*  Create a default CAS session and create SAS librefs for existing caslibs */
/*  so that they are visible in the SAS Studio Libraries tree.               */
/*****************************************************************************/
cas; 
caslib _all_ assign;


/*****************************************************************************/
/* Partition the data into training and validation                           */
/*****************************************************************************/
proc partition data=PUBLIC.NHANES_PAD1 partition samppct=70 seed=1234;
  by PAD_Target;
  output out=PUBLIC.NHANES_PAD_PART copyvars=(_ALL_);
run;

/* Present the partitions on a bar chart */
ods graphics / reset width=6.4in height=4.8in imagemap;
proc sgplot data=  PUBLIC.NHANES_PAD_PART ;
  vbar _PartInd_  / 
    group=PAD_Target groupdisplay=cluster datalabel ;
       yaxis grid ;
run;
ods graphics / reset;


/*****************************************************************************/
/* Feature Engeneering                                                       */
/*****************************************************************************/
data PUBLIC.NHANES_PAD_PART;
set PUBLIC.NHANES_PAD_PART;
    PulsePreassure = BPXSAR - BPXDAR;
    TC_HDL = LBXTC / LBDHDL;
    IF ( (DIQ010 In ('Yes', 'Borderline')) 
      OR (DIQ050 In ('Yes'))
      OR (LBXGH > 6.5 ) 
       ) then Diabetes = 1;
         else Diabetes = 0;
	IF ( BPXSAR >= 140 OR BPXDAR >= 90 ) 
       then Hypertension = 1; else Hypertension = 0;
run;

ods noproctitle;

/*****************************************************************************/
/* Model PAD_Target Gradient Boosting                                        */
/*****************************************************************************/
proc gradboost data=PUBLIC.NHANES_PAD_PART outmodel=public.gb_model;
   partition role= _PartInd_ (validate='1');
   target PAD_Target / level=nominal;
   input RIDAGEMN_Recode PulsePreassure BMXBMI TC_HDL LBXGH Diabetes 
         Hypertension / level=interval;
   input INDHHINC DMDEDUC2 RIDRETH1 DIQ150 DIQ110 SMQ040 ALQ100 
         RIAGENDR / level=nominal;
run;

/************************************************************************/
/* Score the data using the generated GBM model                         */
/************************************************************************/
proc gradboost data=PUBLIC.NHANES_PAD_PART inmodel=public.gb_model noprint;
  output out=PUBLIC.NHANES_PAD_Scored_GB copyvars=(_ALL_);
run;

/************************************************************************/
/* Assess                                                               */
/************************************************************************/
ods noproctitle;
proc assess data=PUBLIC.NHANES_PAD_SCORED_GB nbins = 10   ncuts = 10 ;
   target PAD_Target / event="1" level=nominal;
   input  P_PAD_Target1 ;
          fitstat pvar=P_PAD_Target0 /
          pevent="0" delimiter=" ";
   ods output 
     ROCInfo=WORK._roc_temp LIFTInfo=WORK._lift_temp   ;
run;


data _null_;
   set WORK._roc_temp(obs=1);
   call symput('AUC',round(C,0.01));
run;
proc sgplot data=WORK._roc_temp noautolegend aspect=1;
  title 'ROC Curve (Target = PAD_Target, Event = 1)';
  xaxis label='False positive rate' values=(0 to 1 by 0.1);
  yaxis label='True positive rate' values=(0 to 1 by 0.1);
  lineparm x=0 y=0 slope=1 / transparency=.7 LINEATTRS=(Pattern= 34);
  series  x=fpr y=sensitivity;
  inset "AUC=&AUC"/position = bottomright border;
run;

/* Add a row in lift information table for depth of 0.*/
data WORK._extraPoint;
   depth=0;
   CumResp=0;
run;   
data WORK._lift_temp;
    set WORK._extraPoint  WORK._lift_temp;
run;

/************************************************************************/
/* ROC and Lift Charts using validation data                            */
/************************************************************************/
proc sgplot data=WORK._lift_temp noautolegend;
  title 'Lift Chart (Target = PAD_Target, Event = 1)';
  xaxis label='Population Percentage' ;
  yaxis label='Lift';
  series  x=depth y=lift;
run;

proc sgplot data=WORK._lift_temp noautolegend;
  title 'Cumulative Lift Chart (Target = PAD_Target, Event = 1)';
  xaxis label='Population Percentage' ;
  yaxis label='Lift';
  series  x=depth y=CumLift;
run;

proc sgplot data=WORK._lift_temp noautolegend  aspect=1;
  title 'Cumulative Response Rate (Target = PAD_Target, Event = 1)';
  xaxis label='Population Percentage' ;
  yaxis label='Response Percentage';
  series  x=depth y=CumResp;
  lineparm x=0 y=0 slope=1 / transparency=.7 LINEATTRS=(Pattern= 34);
run;

proc delete data= 
 WORK._extraPoint  WORK._lift_temp  WORK._roc_temp     ;
run;
