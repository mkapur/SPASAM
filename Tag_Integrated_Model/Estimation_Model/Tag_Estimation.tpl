
/////////////////////////////////////////////////////////
// Spatial Estimation Model based on Operating Model by Daniel Goethel (NMFS SEFSC)  
// started by Dana Hanselman (AFSC) //Further screwed up by Jon Deroba (NEFSC)
//////////////////////////////////////////////////////////

GLOBALS_SECTION
  #include "admodel.h"
  #define EOUT(var) cout <<#var<<" "<<var<<endl;

TOP_OF_MAIN_SECTION
  arrmblsize=500000000;
  gradient_structure::set_MAX_NVAR_OFFSET(5000000);
  gradient_structure::set_NUM_DEPENDENT_VARIABLES(5000000);

DATA_SECTION
////////////////////////////////////////////////////////////////////////////////////
/////MODEL STRUCTURE INPUTS/////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////
  init_int nages //number of ages
  init_int nyrs //number of years of catch
  init_int npops //number of populations
///////////// Indices for ragged arrays (can't be type init so need to establish as integer)
  !! int np=npops;
  !! int ny=nyrs;
  !! int na=nages;
//////////////////////////////////////////////////////
  init_ivector nregions(1,np) //number of regions within a population - for metamictic regions = areas, populations = 1
  !! ivector nreg=nregions;
  init_ivector nfleets(1,np) //number of fleets in each region by each population
  !! ivector nf=nfleets;
  init_ivector nfleets_survey(1,np) //number of fleets in each region by each population
  !! ivector nfs=nfleets_survey;

////////////////////////////////////////////////////////////////////////////////////
//////////////SWITCHES//////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////

 
  init_matrix tsurvey(1,np,1,nreg) //time of survey in proportion of year (0,1)
  init_number larval_move_switch
  ///// Changes the type of larval movement pattern (sets age class 1 movements)
  //==0 no movement
  //==1 input movement
  //==2 movement within population only based on residency (symmetric)
  //==3 symmetric movement but only allow movement within a population (ie regions within a population) not across populations
  //==4 symmetric movement across all populations and regions
  //==5 allow movement across all regions and populations, based on population/region specific residency (symmetric off-diag)

  init_number move_switch
  ///// Sets the type of adult movement pattern (sets age class>1 movements)
  //==0 no movement
  //==1 input movement
  //==2 movement within population only based on input residency (symmetric off diagnol)
  //==3 symmetric movement but only allow movement within a population (ie regions within a population) not across populations
  //==4 symmetric movement across all populations and regions
  //==5 allow movement across all regions and populations, based on population/region specific residency (symmetric off diagnol)
  //==6 natal return, based on age of return and return probability (certain fraction of fish make return migration to natal population eg ontogenetic migration)
  //==7 larvae stay in the population that they move to (i.e., for overlap, do not return to natal population if adult movement==0...otherwise with natal
  //    homing would return to natal population because natal residency is 100% and use natal movement rates (not current population movement rates like with metapopulation/random movement))
  //==8 density dependent movement based on relative biomass among potential destination area/regions, partitions (1-input_residency) based on a logistic function of biomass in current area/region and 'suitability' of destination area/regions 
  init_number use_input_Bstar
  //==0 set Bstar for DD movement equal to SSB_zero*SSB_zero_appor (if nreg==1, Bstar=SSB0), **NOTE** for Rec_type!=2 (not BH), defaults to using input_Bstar since no SSB0 calcs are done
  //==1 use input_Bstar

////// Population Structure switches
  init_number natal_homing_switch
  //==0 no natal homing (SSB is sum of SSB in population regardless of natal origin; weight/mat/fecund/ are based on current population not natal population) - Metapopulation/metamictic
  //==1 do natal homing (a fish only adds to SSB if it is in its natal population at spawning time; weight/mat/fecund/ are based on natal population) - Natal homing
  //natal homing  assumes genetic based life history and contribution to SSB (i.e., natal homing and no demographic mixing), natal homing==0 assumes demographic mixing (e.g. metapopulations where life history is more location based)

  init_number spawn_return_switch
   //==0 if natal_homing_switch==1 then only fish that are in natal population add to SSB
   //==1 natal_homing_switch==1 a fraction of fish return to natal population to spawn (inpsantaneous migration to natal population and back at time of spawning) based spawn_return_prob; weight/mat/fecund/ are based on natal population)
//////////////////////////////////////////////////////

  init_number select_switch
  //==0 input selectivity
  //==1 logistic selectivity based on input sel_beta1 and sel_beta2
  //==2 double logistic selectivity based on input sel_beta1, sel_beta2, sel_beta3 and sel_beta4
/////////////////////////////////////////////////////
// I don't think we are going to experiment with any F switches for estimation model??
//dhdhdhdhdhdhdhdh//
//my notes say we'll estimate a fully selected F for each fleet, year, region.  And so no need for F switches.  //JJD

 // init_number F_switch
  //==1 input F
  //==2 input single overall F (FMSY)
  //==3 Estimate F that minimizes difference in input and estimated total harvest rate
  //==4 overall F (FMSY) is split evenly among populations (each fleet uses population F)
  //==5 overall F (FMSY) is is split evenly among all regions (each fleet uses region F)
  //==6 overall F (FMSY) is split evenly among fleets
  //==7 F devs about input F based on sigma_F
  //==8 random walk in F
  
  //dhdhdhdhhdhdhdhdhdhddhdhdh
  //weight based only remove this switch?
  //dhdhdhdhdhdhdhdhd
  //We are definitely only using weight based, but the OM and EM code still both require an input value for this in some nested if-statements.  Maybe easier just to make sure always ==2 than delete everywhere //JJD
  //Nothing wrong with keeping some code we're not using now, but somebody might later //JJD
  init_number SSB_type
  //==1 fecundity based SSB
  //==2 weight based SSB
  
     //dhdhdhdhdhdhdhdhdhddhdhdhd
  // Likewise, are we doing both recruitment styles?
  //dhdhdhdhdhdhdhdhdhdhdhdhdhdhd
  //Same reply comment as for SSB_type switch //JJD

  init_number Rec_type
  //==1 stock-recruit relationship assumes an average value based on R_ave
  //==2 Beverton-Holt population-recruit functions based on population-specific input steepness, R0 (R_ave), M, and weight
  //==3 environmental recruitment - sine fucntion based on amplitude and frequency

  
///////////////////////////////////////////////////////////////////////////////
////////READ IN THE DATA  //////////////////////////////////
///////////////////////////////////////////////////////////////////////////////

/////tagging data parameters
  init_int nyrs_release //number of years with tag release events
  !! int ny_rel=nyrs_release;
  init_vector yrs_releases(1,ny_rel) //vector containing the model years with releases
  init_int max_life_tags //number of years that tag recaptures will be tallied for after release (assume proportional to longevity of the species)...use this to avoid calculating tag recaptures for all remaining model years after release since # recaptures are often extremely limited after a few years after release
  init_3darray report_rate(1,np,1,ny_rel,1,nreg) //tag reporting rate (assume constant for all recaptures within a given release cohort, but can be variable across populations or regions)...could switch to allow variation across fleets instead

//##########################################################################################################################################
//#########################################################################################################################################
//##########################################################################################################################################
//#########################################################################################################################################
//######### FOR NATAL HOMING THERE IS NO ACCOUNTING OF REGIONAL DIFFERENCES IN VITAL RATES ACROSS REGIONS WITHIN A POPULATION
//######### IE BECAUSE GENETICS DEFINE VITAL RATES, THEY MUST ALL BE THE SAME
//######### **********DO NOT INPUT REGIONALLY VARYING VITAL RATES, NATAL REGION WILL NOT BE PROPERLY TRACKED IN SSB CALCS #############
//#########################################################################################################################################
  //dhdhdhdhdhd
  // are these the same in all our models? 
  // dhdhdhhdh
  //No //JJD
  ////////////////BIOLOGICAL PARAMETERS////////////////
  /////////////////////////////////////////////////////
  init_3darray input_weight(1,np,1,nreg,1,na)  
  init_3darray input_catch_weight(1,np,1,nreg,1,na)
  init_3darray fecundity(1,np,1,nreg,1,na)
  init_3darray maturity(1,np,1,nreg,1,na)
  init_matrix prop_fem(1,np,1,nreg) //proportion of population assumed to be female for SSB calcs (typically use 0.5)
  //##########################################################################################################################################
//#########################################################################################################################################
//##########################################################################################################################################
//#########################################################################################################################################
 //// CATCH DATA //////////////////////

 //fill in a vector of years
  vector years(1,nyrs)
  !!years.fill_seqadd(double(1),1.0);

 //I don't think we need this because it's used to generate tag recaps, but these will be input for EM.  //JJD
   // init_imatrix nregions_temp(1,np,1,np) //used to fill tag_recap matrices

 // !! for(int j=1;j<=npops;j++) //recap stock
 // !! {
//  !!  for (int r=1;r<=npops;r++) //recap region
 // !!  {
//  !!    if(j<=r)
 // !!     {
 // !!     nregions_temp(j,r)=0;
 // !!     }
 // !!    if(j>r)
 // !!     {
 // !!     nregions_temp(j,r)=nreg(j-1); //create temp matrix that holds the number of regions that exist in all previous populations (so can sum for use in calcs below)
 // !!     }
 // !!   }
 // !!  }
 // ivector nreg_temp(1,np)

 //I didn't give any thought to whether all of these are still required; just left them //JJD
  int a
  int y
  int z
  int k
  int j
  int i
  int s
  int r
  int n
  int w
  int p
  int v
  int x
  int uu
  int d
  int xx

 !! cout << "debug = " << debug << endl;
 !! cout << "If debug != 1541 then .dat file not setup correctly" << endl;
 !! cout << "input read" << endl;


  !! ivector nr=nregions;
  !! int nps=npops;
  !! int nyr=nyrs;
  !! int nag=nages;
  !! ivector nfl=nfleets;
  !! ivector nfls=nfleets_survey;  
  !! int nyr_rel=nyrs_release;
  !! int nt=max_life_tags*sum(nregions)+1;
  !! int nt2=nt-1;
  !! int tag_age=max_life_tags;

 
 
 // vitals
 6darray T(1,nps,1,nr,1,nyr,1,nag,1,nps,1,nr) //maybe needed depending on how movement parameterized? //JJD
 6darray rel_bio(1,nps,1,nr,1,nyr,1,nag,1,nps,1,nr) //maybe needed depending on how movement parameterized? //JJD
 matrix Bstar(1,nps,1,nr) //maybe needed depending on how movement parameterized? //JJD
 matrix c(1,nps,1,nr) //maybe needed depending on how movement parameterized? //JJD
 4darray Fract_Move_DD(1,nps,1,nr,1,nyr,1,nag) //maybe needed depending on how movement parameterized? //JJD
 //5darray selectivity(1,nps,1,nr,1,nyr,1,nag,1,nfl)
 //4darray F_year(1,nps,1,nr,1,nyr,1,nfl)
 5darray F_fleet(1,nps,1,nr,1,nyr,1,nag,1,nfl)
 //4darray F(1,nps,1,nr,1,nyr,1,nag)
 4darray M(1,nps,1,nr,1,nyr,1,nag)
 matrix rec_devs(1,nps,1,nyr)
 //matrix rec_devs_randwalk(1,nps,1,nyr)
 //4darray weight_population(1,nps,1,nr,1,nyr,1,nag)
 //4darray weight_catch(1,nps,1,nr,1,nyr,1,nag)
 3darray wt_mat_mult(1,nps,1,nyr,1,nag)
 4darray wt_mat_mult_reg(1,nps,1,nr,1,nyr,1,nag)
 3darray ave_mat_temp(1,nps,1,nag,1,nr) //to calc average maturity //might need to retain depending on how we end up calculated ref points and SPR stuff //JJD
 matrix ave_mat(1,nps,1,nag) //to calc average maturity //might need to retain depending on how we end up calculated ref points and SPR stuff //JJD
 matrix SPR_N(1,nps,1,nag) //might need to retain depending on how we end up calculated ref points and SPR stuff //JJD
 matrix SPR_SSB(1,nps,1,nag) //might need to retain depending on how we end up calculated ref points and SPR stuff //JJD
 vector SPR(1,nps) //might need to retain depending on how we end up calculated ref points and SPR stuff //JJD
 vector SSB_zero(1,nps) //might need to retain depending on how we end up calculated ref points and SPR stuff //JJD
 vector alpha(1,nps)
 vector beta(1,nps)

//JJD stopped here on May 22, 2017

//recruitment 
 3darray recruits_BM(1,nps,1,nr,1,nyr)
 3darray recruits_AM(1,nps,1,nr,1,nyr)
 3darray Rec_Prop(1,nps,1,nr,1,nyr)
 3darray Rec_prop_temp1(1,nps,1,nyr,1,nr)
 3darray Rec_prop_temp2(1,nps,1,nyr,1,nr)

 3darray rec_index_BM(1,nps,1,nr,1,nyr)
 3darray rec_index_prop_BM(1,nps,1,nr,1,nyr)
 3darray rec_index_BM_temp(1,nps,1,nyr,1,nr)
 3darray rec_index_AM(1,nps,1,nr,1,nyr)
 3darray rec_index_prop_AM(1,nps,1,nr,1,nyr)
 3darray rec_index_AM_temp(1,nps,1,nyr,1,nr)

 vector env_rec(1,nyr)

//abundance 
 4darray abundance_at_age_BM(1,nps,1,nr,1,nyr,1,nag)
 4darray abundance_at_age_AM(1,nps,1,nr,1,nyr,1,nag)
 4darray abundance_in(1,nps,1,nr,1,nyr,1,nag)
 4darray abundance_res(1,nps,1,nr,1,nyr,1,nag)
 4darray abundance_leave(1,nps,1,nr,1,nyr,1,nag)
 4darray abundance_spawn(1,nps,1,nr,1,nyr,1,nag)

//biomass
 4darray biomass_BM_age(1,nps,1,nr,1,nyr,1,nag)
 4darray biomass_AM_age(1,nps,1,nr,1,nyr,1,nag)
 3darray biomass_BM(1,nps,1,nr,1,nyr)
 3darray biomass_AM(1,nps,1,nr,1,nyr)
 4darray bio_in(1,nps,1,nr,1,nyr,1,nag)
 4darray bio_res(1,nps,1,nr,1,nyr,1,nag)
 4darray bio_leave(1,nps,1,nr,1,nyr,1,nag)

 //tagging data
  vector ntags_total(1,nyr_rel)
  4darray ntags(1,nps,1,nr,1,nyr_rel,1,nag)
  7darray tags_avail(1,nps,1,nr,1,nyr_rel,1,nag,1,tag_age,1,nps,1,nr)
  7darray recaps(1,nps,1,nr,1,nyr_rel,1,nag,1,tag_age,1,nps,1,nr)
  4darray total_rec(1,nps,1,nr,1,nyr_rel,1,nag)
  4darray not_rec(1,nps,1,nr,1,nyr_rel,1,nag)
  7darray tag_prop(1,nps,1,nr,1,nyr_rel,1,nag,1,tag_age,1,nps,1,nr)
  4darray tag_prop_not_rec(1,nps,1,nr,1,nyr_rel,1,nag)
  5darray tag_prop_final(1,nps,1,nr,1,nyr_rel,1,nag,1,nt)
  5darray SIM_tag_prop(1,nps,1,nr,1,nyr_rel,1,nag,1,nt)
  5darray OBS_tag_prop_final(1,nps,1,nr,1,nyr_rel,1,nag,1,nt)

 //survey index
 5darray survey_selectivity(1,nps,1,nr,1,nyr,1,nag,1,nfls)
 6darray true_survey_fleet_overlap_age(1,nps,1,nps,1,nr,1,nyr,1,nfls,1,nag)
 6darray survey_at_age_region_fleet_overlap_prop(1,nps,1,nps,1,nr,1,nfls,1,nyr,1,nag)
 6darray SIM_survey_prop_overlap(1,nps,1,nps,1,nr,1,nfls,1,nyr,1,nag)
 6darray OBS_survey_prop_overlap(1,nps,1,nps,1,nr,1,nfls,1,nyr,1,nag)
 6darray true_survey_fleet_overlap_age_bio(1,nps,1,nps,1,nr,1,nyr,1,nfls,1,nag)
 5darray true_survey_fleet_bio_overlap(1,nps,1,nps,1,nr,1,nyr,1,nfls)
 4darray true_survey_region_bio_overlap(1,nps,1,nps,1,nyr,1,nr)
 3darray true_survey_population_bio_overlap(1,nps,1,nyr,1,nps)
 matrix true_survey_natal_bio_overlap(1,nyr,1,nps)
 vector true_survey_total_bio_overlap(1,nyr)
 5darray true_survey_fleet_age(1,nps,1,nr,1,nyr,1,nfls,1,nag)
 5darray survey_at_age_fleet_prop(1,nps,1,nr,1,nyr,1,nfls,1,nag)
 5darray SIM_survey_prop(1,nps,1,nr,1,nfls,1,nyr,1,nag)
 5darray OBS_survey_prop(1,nps,1,nr,1,nfls,1,nyr,1,nag)
 5darray true_survey_fleet_age_bio(1,nps,1,nr,1,nyr,1,nfls,1,nag)
 4darray true_survey_fleet_bio(1,nps,1,nr,1,nyr,1,nfls)
 3darray true_survey_region_bio(1,nps,1,nyr,1,nr)
 matrix true_survey_population_bio(1,nyr,1,nps)
 vector true_survey_total_bio(1,nyr)
 5darray OBS_survey_fleet_bio_overlap(1,nps,1,nps,1,nr,1,nyr,1,nfls)
 4darray OBS_survey_region_bio_overlap(1,nps,1,nps,1,nyr,1,nr)
 3darray OBS_survey_population_bio_overlap(1,nps,1,nyr,1,nps)
 matrix OBS_survey_natal_bio_overlap(1,nyr,1,nps)
 vector OBS_survey_total_bio_overlap(1,nyr)
 4darray OBS_survey_fleet_bio(1,nps,1,nr,1,nyr,1,nfls)
 3darray OBS_survey_region_bio(1,nps,1,nyr,1,nr)
 matrix OBS_survey_population_bio(1,nyr,1,nps)
 vector OBS_survey_total_bio(1,nyr)
 3darray apport_region_survey_biomass(1,nps,1,nr,1,nyr)

 //yield & BRP calcs 
 5darray catch_at_age_fleet(1,nps,1,nr,1,nyr,1,nag,1,nfl)
 5darray catch_at_age_fleet_prop(1,nps,1,nr,1,nyr,1,nfl,1,nag)
 5darray SIM_catch_prop(1,nps,1,nr,1,nfl,1,nyr,1,nag)
 5darray OBS_catch_prop(1,nps,1,nr,1,nfl,1,nyr,1,nag)
 4darray yield_fleet(1,nps,1,nr,1,nyr,1,nfl)
 4darray catch_at_age_region(1,nps,1,nr,1,nyr,1,nag)
 4darray catch_at_age_region_prop(1,nps,1,nr,1,nyr,1,nag)
 3darray yield_region(1,nps,1,nr,1,nyr)
 3darray catch_at_age_population(1,nps,1,nyr,1,nag)
 3darray catch_at_age_population_prop(1,nps,1,nyr,1,nag)
 matrix yield_population(1,nps,1,nyr)
 3darray SSB_region(1,nps,1,nr,1,nyr)
 matrix SSB_population(1,nps,1,nyr)
 vector SSB_total(1,nyr)
 3darray abundance_population(1,nps,1,nyr,1,nag)
 matrix abundance_total(1,nyr,1,nag)
 matrix biomass_population(1,nps,1,nyr)
 vector biomass_total(1,nyr)
 matrix catch_at_age_total(1,nyr,1,nag)
 matrix catch_at_age_total_prop(1,nyr,1,nag)
 vector yield_total(1,nyr)
 4darray harvest_rate_region_num(1,nps,1,nr,1,nyr,1,nag)
 3darray harvest_rate_population_num(1,nps,1,nyr,1,nag)
 matrix harvest_rate_total_num(1,nyr,1,nag)
 3darray harvest_rate_region_bio(1,nps,1,nr,1,nyr)
 matrix harvest_rate_population_bio(1,nps,1,nyr)
 vector harvest_rate_total_bio(1,nyr)
 3darray depletion_region(1,nps,1,nr,1,nyr)
 matrix depletion_population(1,nps,1,nyr)
 vector depletion_total(1,nyr)
 5darray abundance_at_age_BM_overlap_region(1,nps,1,nps,1,nyr,1,nag,1,nr)
 4darray abundance_at_age_BM_overlap_population(1,nps,1,nps,1,nyr,1,nag)
 5darray abundance_at_age_AM_overlap_region(1,nps,1,nps,1,nyr,1,nag,1,nr)
 4darray abundance_at_age_AM_overlap_population(1,nps,1,nps,1,nyr,1,nag)
 4darray abundance_AM_overlap_region_all_natal(1,nps,1,nr,1,nyr,1,nag)
 5darray abundance_spawn_overlap(1,nps,1,nps,1,nr,1,nyr,1,nag)
 4darray SSB_region_overlap(1,nps,1,nps,1,nr,1,nyr)
 3darray SSB_population_overlap(1,nps,1,nps,1,nyr)
 matrix SSB_natal_overlap(1,nps,1,nyr)

 6darray catch_at_age_region_fleet_overlap(1,nps,1,nps,1,nr,1,nfl,1,nyr,1,nag)
 6darray catch_at_age_region_fleet_overlap_prop(1,nps,1,nps,1,nr,1,nfl,1,nyr,1,nag)
 6darray SIM_catch_prop_overlap(1,nps,1,nps,1,nr,1,nfl,1,nyr,1,nag)
 6darray OBS_catch_prop_overlap(1,nps,1,nps,1,nr,1,nfl,1,nyr,1,nag)
 5darray catch_at_age_region_overlap(1,nps,1,nps,1,nr,1,nyr,1,nag)
 5darray catch_at_age_region_overlap_prop(1,nps,1,nps,1,nr,1,nyr,1,nag)
 5darray yield_region_fleet_overlap(1,nps,1,nps,1,nr,1,nfl,1,nyr)
 4darray yield_region_overlap(1,nps,1,nps,1,nr,1,nyr)
 4darray catch_at_age_population_overlap(1,nps,1,nps,1,nyr,1,nag)
 4darray catch_at_age_population_overlap_prop(1,nps,1,nps,1,nyr,1,nag)
 3darray yield_population_overlap(1,nps,1,nps,1,nyr)
 3darray abundance_natal_overlap(1,nps,1,nyr,1,nag)
 5darray biomass_BM_age_overlap(1,nps,1,nps,1,nr,1,nyr,1,nag)
 5darray biomass_AM_age_overlap(1,nps,1,nps,1,nr,1,nyr,1,nag)
 4darray biomass_BM_overlap_region(1,nps,1,nps,1,nr,1,nyr)
 4darray biomass_AM_overlap_region(1,nps,1,nps,1,nr,1,nyr)
 5darray biomass_AM_overlap_region_all_natal_temp(1,nps,1,nr,1,nyr,1,nag,1,nps)
 4darray biomass_AM_overlap_age_region_all_natal(1,nps,1,nr,1,nyr,1,nag)
 3darray biomass_AM_overlap_region_all_natal(1,nps,1,nr,1,nyr)
 3darray biomass_population_overlap(1,nps,1,nps,1,nyr)
 matrix biomass_natal_overlap(1,nps,1,nyr)
 3darray catch_at_age_natal_overlap(1,nps,1,nyr,1,nag)
 3darray catch_at_age_natal_overlap_prop(1,nps,1,nyr,1,nag)
 matrix yield_natal_overlap(1,nps,1,nyr)
 5darray harvest_rate_region_fleet_bio_overlap(1,nps,1,nps,1,nr,1,nfl,1,nyr)
 4darray harvest_rate_region_bio_overlap(1,nps,1,nps,1,nr,1,nyr)
 3darray harvest_rate_population_bio_overlap(1,nps,1,nps,1,nyr)
 matrix harvest_rate_natal_bio_overlap(1,nps,1,nyr)
 4darray depletion_region_overlap(1,nps,1,nps,1,nr,1,nyr)
 3darray depletion_population_overlap(1,nps,1,nps,1,nyr)
 matrix depletion_natal_overlap(1,nps,1,nyr)
 3darray Bratio_population_overlap(1,nps,1,nps,1,nyr)
 matrix Bratio_natal_overlap(1,nps,1,nyr)
 matrix Bratio_population(1,nps,1,nyr)
 vector Bratio_total(1,nyr)

 //Observed Yield
 5darray OBS_yield_region_fleet_overlap(1,nps,1,nps,1,nr,1,nyr,1,nfl)
 4darray OBS_yield_region_overlap(1,nps,1,nps,1,nyr,1,nr)
 3darray OBS_yield_population_overlap(1,nps,1,nyr,1,nps)
 matrix OBS_yield_natal_overlap(1,nyr,1,nps)
 vector OBS_yield_total_overlap(1,nyr)
 4darray OBS_yield_fleet(1,nps,1,nr,1,nyr,1,nfl)
 3darray OBS_yield_region(1,nps,1,nyr,1,nr)
 matrix OBS_yield_population(1,nyr,1,nps)
 vector OBS_yield_total(1,nyr)
 3darray apport_yield_region(1,nps,1,nr,1,nyr)

 matrix biomass_BM_temp(1,nps,1,nr)
 number biomass_BM_temp2
 5darray biomass_BM_overlap_temp(1,nps,1,nr,1,nyr,1,nag,1,nps)
 4darray init_abund_temp(1,nps,1,nr,1,nag,1,nps)
 5darray rand_SIM_survey_prop_temp(1,nps,1,nr,1,nyr,1,nfls,1,2000) //should make function of max(ncatch) but had issues making an index, used 2000 as placeholder since nsurvey unlikely to exceed 2000
 6darray rand_SIM_survey_prop_temp_overlap(1,nps,1,nps,1,nr,1,nyr,1,nfls,1,2000) //should make function of max(ncatch) but had issues making an index, used 2000 as placeholder since nsurvey unlikely to exceed 2000
 5darray rand_SIM_catch_prop_temp(1,nps,1,nr,1,nyr,1,nfl,1,2000) //should make function of max(ncatch) but had issues making an index
 6darray rand_SIM_catch_prop_temp_overlap(1,nps,1,nps,1,nr,1,nyr,1,nfl,1,2000) //should make function of max(ncatch) but had issues making an index
 vector rand_SIM_survey_prop_temp2(1,nages)
 vector rand_SIM_catch_prop_temp2(1,nages)
 5darray OBS_survey_fleet_bio_temp(1,nps,1,nr,1,nyr,1,nfls,1,nps)
 5darray true_survey_fleet_bio_overlap_temp(1,nps,1,nr,1,nyr,1,nfls,1,nps)
 5darray catch_at_age_fleet_prop_temp(1,nps,1,nr,1,nyr,1,nfl,1,nag)
 matrix abundance_move_temp(1,nps,1,nr)
 matrix bio_move_temp(1,nps,1,nr)
 5darray yield_fleet_temp(1,nps,1,nr,1,nyr,1,nfl,1,nag)
 4darray yield_region_temp(1,nps,1,nr,1,nyr,1,nag)
 3darray yield_population_temp(1,nps,1,nyr,1,nag)
 4darray SSB_region_temp(1,nps,1,nr,1,nyr,1,nag)
 matrix SSB_total_temp(1,nyr,1,nps)
 4darray abundance_population_temp(1,nps,1,nyr,1,nag,1,nr)
 3darray abundance_total_temp(1,nyr,1,nag,1,nps)
 3darray biomass_population_temp(1,nps,1,nyr,1,nr)
 matrix biomass_total_temp(1,nyr,1,nps)
 3darray catch_at_age_total_temp(1,nyr,1,nag,1,nps)
 matrix yield_total_temp(1,nyr,1,nps)
 4darray catch_at_age_population_temp(1,nps,1,nyr,1,nag,1,nr)
 5darray SSB_region_temp_overlap(1,nps,1,nps,1,nr,1,nyr,1,nag)
 matrix abundance_move_overlap_temp(1,nps,1,nr)
 5darray OBS_yield_fleet_temp(1,nps,1,nr,1,nyr,1,nfl,1,nps)
 6darray yield_region_fleet_temp_overlap(1,nps,1,nps,1,nr,1,nfl,1,nyr,1,nag)
 5darray yield_region_temp_overlap(1,nps,1,nps,1,nr,1,nyr,1,nag)
 4darray yield_population_temp_overlap(1,nps,1,nps,1,nyr,1,nag)
 4darray abundance_natal_temp_overlap(1,nps,1,nyr,1,nag,1,nps)
 4darray biomass_population_temp_overlap(1,nps,1,nps,1,nyr,1,nr)
 3darray biomass_natal_temp_overlap(1,nps,1,nyr,1,nps)
 4darray catch_at_age_natal_temp_overlap(1,nps,1,nyr,1,nag,1,nps)
 3darray yield_natal_temp_overlap(1,nps,1,nyr,1,nps)
 5darray catch_at_age_population_temp_overlap(1,nps,1,nps,1,nyr,1,nag,1,nr)
 3darray SSB_natal_overlap_temp(1,nps,1,nyr,1,nps)
 matrix SSB_overlap_natal(1,nps,1,nr)
 5darray abundance_AM_overlap_region_all_natal_temp(1,nps,1,nr,1,nyr,1,nag,1,nps)
 3darray SSB_population_temp(1,nps,1,nyr,1,nr)
 4darray SSB_population_temp_overlap(1,nps,1,nps,1,nyr,1,nr)

 5darray rand_tag_prop_temp(1,nps,1,nr,1,nyr_rel,1,nag,1,2000) //should make function of max(ncatch) but had issues making an index
 vector rand_tag_prop_temp2(1,nt)
 3darray total_recap_temp(1,nps,1,tag_age,1,nr)
 matrix tags_avail_temp(1,nps,1,nr)
 3darray tag_prop_temp(1,nps,1,nyr_rel,1,nr)
 vector tag_prop_temp2(1,nt2)
 
 4darray res_TAC(1,nps,1,nr,1,nfl,1,nyr)
 3darray res_u(1,nps,1,nr,1,nyr)
 number Fnew
 number delt
 number fofF
 number fprimeF
 vector fofFvect(1,nag)
 vector fprimeFhigh(1,nag)
 vector fprimeFlow(1,nag)
 4darray TAC(1,nps,1,nr,1,nfl,1,nyr)
 3darray u(1,nps,1,nr,1,nfl) // already declared u above as int
 4darray yield_RN(1,nps,1,nr,1,nyr,1,nfl)
 5darray yield_RN_overlap(1,nps,1,nps,1,nr,1,nyr,1,nfl)
 4darray survey_RN(1,nps,1,nr,1,nyr,1,nfls)
 5darray survey_RN_overlap(1,nps,1,nps,1,nr,1,nyr,1,nfls)
 4darray F_RN(1,nps,1,nr,1,nyr,1,nfl)
 matrix rec_devs_RN(1,nps,1,nyr)
 3darray Rec_apport_RN(1,nps,1,nyr,1,nr)
 3darray rec_index_RN(1,nps,1,nr,1,nyr)
PARAMETER_SECTION
 
 init_matrix F_est(1,npops,1,nregions,phase_F)

 init_number dummy(phase_dummy)

  objective_function_value f

 !! cout << "parameters set" << endl;
 

INITIALIZATION_SECTION  //set initial values
     
  F_est .7;
  dummy 1;

PROCEDURE_SECTION

  get_random_numbers();
  get_movement();
  get_selectivity();
  get_F_age();
  get_vitals();
  get_SPR();
  get_env_Rec();
  get_DD_move_parameters();
  get_abundance();
  get_rand_survey_CAA_prop();
  get_rand_CAA_prop();
  get_tag_recaptures();
  get_observed_tag_recaptures();
  evaluate_the_objective_function();
 

FUNCTION get_random_numbers
   random_number_generator myrand_yield(myseed_yield);
   random_number_generator myrand_survey(myseed_survey);
   random_number_generator myrand_F(myseed_F);
   random_number_generator myrand_rec_devs(myseed_rec_devs);
   random_number_generator myrand_rec_apport(myseed_rec_apport);
   random_number_generator myrand_rec_index(myseed_rec_index);

  for (int p=1;p<=npops;p++)
   {
    for (int j=1;j<=npops;j++)
     {  
      for (int r=1;r<=nregions(j);r++)   
       {       
        for (int y=1;y<=nyrs;y++)
         {
          for (int z=1;z<=nfleets(j);z++)
           {
            for (int x=1;x<=nfleets_survey(j);x++)
             {
              yield_RN(j,r,y,z)=randn(myrand_yield);
              yield_RN_overlap(p,j,r,y,z)=randn(myrand_yield);
              survey_RN(j,r,y,x)=randn(myrand_survey);
              survey_RN_overlap(p,j,r,y,x)=randn(myrand_survey);
              F_RN(j,r,y,z)=randn(myrand_F);
              rec_devs_RN(j,y)=randn(myrand_rec_devs);
               if(apportionment_type==3)//completely random apportionment
                {
                 Rec_apport_RN(j,y,r)=randu(myrand_rec_apport);//generate a positive random number bw 0-1
                }
               if(apportionment_type==4)//completely random apportionment
                {
                 Rec_apport_RN(j,y,r)=randn(myrand_rec_apport);//generate a positive random number bw 0-1
               }
              rec_index_RN(j,r,y)=randn(myrand_rec_index);
             }
           }
         }
       }
     }
    }

///////BUILD MOVEMENT MATRIX////////
FUNCTION get_movement

//POSSIBLE ADDITIONS:
  //new functional forms
  //simulate yearly differences and age-based movement
  //random movement same as a random F value
  //random walk
  //denpity dependent
  //yearly deviationp around an input average value (e.g., unidirectional movement with yearly deviationp based on a variance term and lognormal distribution)
  //need to enpure random values still sum to 1 for an area (relativization of values)
  for (int j=1;j<=npops;j++)
   {
    for (int r=1;r<=nregions(j);r++)
     {
      for (int y=1;y<=nyrs;y++)
       {
        for (int a=1;a<=nages;a++)
         {
          for (int k=1;k<=npops;k++)
           {
            for (int n=1;n<=nregions(k);n++)
             {
               if(a==1) // allow different movement from adults
                {
                 if(larval_move_switch==0)  //fix at no movement
                  {
                   if(j==k && r==n)
                    {
                     T(j,r,y,a,k,n)=1;
                    }
                   else
                    {
                     T(j,r,y,a,k,n)=0;
                    }
                   }
                 if(larval_move_switch==1) // use input movement
                  {
                   T(j,r,y,a,k,n)=input_T(j,r,a,k,n);
                  }
                 if(larval_move_switch==2) // only allow movement within a population (ie regionp within a population) not across populations based on input residency term
                  {
                   if(j==k && r==n)
                   {
                    T(j,r,y,a,k,n)=input_residency_larval(j,r);
                   }
                   if(j==k && r!=n)
                   {
                    T(j,r,y,a,k,n)=(1-input_residency_larval(j,r))/(nregions(j)-1);
                   }
                   if(j!=k)
                   {
                    T(j,r,y,a,k,n)=0;
                   }
                  }
                 if(larval_move_switch==3) //symmetric movement but only allow movement within a population (ie regionp within a population) not across populations
                  {
                   if(j==k)
                   {
                    T(j,r,y,a,k,n)=1/(nregions(j));
                   }
                   if(j!=k)
                   {
                    T(j,r,y,a,k,n)=0;
                   }
                  }
                 if(larval_move_switch==4) //symmetric movement across all populations and regionp
                  {
                   T(j,r,y,a,k,n)=1/sum(nregions);
                  }
                 if(larval_move_switch==5) // allow movement across all regions and populations, based on population/region specific residency
                  {
                   if(j==k && r==n)
                   {
                    T(j,r,y,a,k,n)=input_residency_larval(j,r);
                   }
                   else
                   {
                    T(j,r,y,a,k,n)=(1-input_residency_larval(j,r))/(sum(nregions)-1);
                   }
                  }
                }
               else
                {                 
                 if(move_switch==0)  //fix at no movement
                  {
                   if(j==k && r==n)
                    {
                     T(j,r,y,a,k,n)=1;
                    }
                   else
                    {
                     T(j,r,y,a,k,n)=0;
                    }
                  }
                 if(move_switch==1) // use input movement
                  {
                   T(j,r,y,a,k,n)=input_T(j,r,a,k,n);
                  }
                 if(move_switch==2) // only allow movement within a population (ie regions within a population) not across populations based on input residency term
                  {
                   if(j==k && r==n)
                   {
                    T(j,r,y,a,k,n)=input_residency(j,r,a);
                   }
                   if(j==k && r!=n)
                   {
                    T(j,r,y,a,k,n)=(1-input_residency(j,r,a))/(nregions(j)-1);
                   }
                   if(j!=k)
                   {
                    T(j,r,y,a,k,n)=0;
                   }
                  }
                 if(move_switch==3) //symmetric movement but only allow movement within a population (ie regionp within a population) not across populations based on input residency term
                  {
                   if(j==k)
                   {
                    T(j,r,y,a,k,n)=1/(nregions(j));
                   }
                   if(j!=k)
                   {
                    T(j,r,y,a,k,n)=0;
                   }
                  }
                 if(move_switch==4) //symmetric movement across all populations and regions
                  {
                   T(j,r,y,a,k,n)=1/sum(nregions);
                  }
                 if(move_switch==5) // allow movement across all regions and populations, based on population/region specific residency
                  {
                   if(j==k && r==n)
                   {
                    T(j,r,y,a,k,n)=input_residency(j,r,a);
                   }
                   else
                   {
                    T(j,r,y,a,k,n)=(1-input_residency(j,r,a))/(sum(nregions)-1);
                   }
                  }              
                }
       }
      } 
     }
    }
   }
  }

///////SELECTIVITY CALCULATIONS///////
FUNCTION get_selectivity
//POSSIBLE ADDITIONS:
  //yearly selectivity
  
//fishery selectivity
  for (int j=1;j<=npops;j++)
   {
    for (int r=1;r<=nregions(j);r++)
     {
      for (int y=1;y<=nyrs;y++)
        {
         for (int a=1;a<=nages;a++)
           {
            for (int z=1;z<=nfleets(j);z++)
              {
               if(select_switch==2) //4 parameter double logistic selectivity
                {
                 selectivity(j,r,y,a,z)=1/((1+mfexp(-sel_beta1(j,r,z)*(a-sel_beta2(j,r,z))))*(1+mfexp(-sel_beta3(j,r,z)*(a-sel_beta4(j,r,z)))));
                }
                if(select_switch==1) //two parameter logistic selectivity
                {
                 selectivity(j,r,y,a,z)=1/(1+mfexp(-sel_beta1(j,r,z)*(a-sel_beta2(j,r,z))));
                //selectivity(j,r,y,a,z)=1/(1+mfexp(-log(19)*(a-(sel_beta1(j,r,z)))/(sel_beta2(j,r,z)))); 
                }
                if(select_switch==0) //input selectivity at age constant by year
                {
                 selectivity(j,r,y,a,z)=input_selectivity(j,r,a,z);
                }
              }
            }
          }
        }
      }

//survey selectivity - always input for now but can adjust later if wanted
 for (int j=1;j<=npops;j++)
    {
     for (int r=1;r<=nregions(j);r++)
      {
       for (int y=1;y<=nyrs;y++)
         {
          for (int a=1;a<=nages;a++)
            {
             for (int z=1;z<=nfleets_survey(j);z++)
               {
                survey_selectivity(j,r,y,a,z)=input_survey_selectivity(j,r,a,z);
              }
             }
            }
          }
        }


///////FISHING MORTALITY CALCULATIONS///////
FUNCTION get_F_age

  for (int j=1;j<=npops;j++)
   {
    for (int r=1;r<=nregions(j);r++)
     {
      for (int y=1;y<=nyrs;y++)
       {
        for (int a=1;a<=nages;a++)
         {
          for (int z=1;z<=nfleets(j);z++)
           { 
             if(F_switch==1) //input F directly
              {
               F_year(j,r,y,z)=input_F(j,r,z);
              }
             if(F_switch==2) //input single yearly F (i.e., using single population FMSY for all populations)
              {
               F_year(j,r,y,z)=input_F_MSY;
              }
             if(F_switch==3) //estimate F that achieves desired Total F
              {
               F_year(j,r,y,z)=value(F_est(j,r));
              }
             if(F_switch==4) //split F_MSY by npops
              {
               F_year(j,r,y,z)=input_F_MSY/npops;
              }
             if(F_switch==5) //split F_MSY by total number of regionp
              {
               F_year(j,r,y,z)=input_F_MSY/sum(nregions);
              }
             if(F_switch==6) //split F_MSY by total number of fleets
              {
               F_year(j,r,y,z)=input_F_MSY/sum(nfleets);
              }
             if(F_switch==7) //F devs about input F based on sigma_F
              {
               F_year(j,r,y,z)=input_F(j,r,z)*mfexp(F_RN(j,r,y,z)*sigma_F(j,r,z)-0.5*square(sigma_F(j,r,z)));
              }
             if(F_switch==8) //random walk in F
              {
               F_year(j,r,y,z)=F_rho(j,r,z)*F_year(j,r,y-1,z)*mfexp(F_RN(j,r,y,z)*sigma_F(j,r,z)-0.5*square(sigma_F(j,r,z)));
              }
             if(F_switch==9)  //Dunce cap F
              {
               Fstartyr=dunce_F(1);
               minF=dunce_F(2);
               maxF=dunce_F(3);
               stepF=(maxF-minF)/((nyrs-Fstartyr)/2);
              if(y<Fstartyr)
               {
                F_year(j,r,y,z)=0;
               }
               if(y>=Fstartyr)
               {
               if(y<((nyrs-Fstartyr)/2+Fstartyr))
                {
                 F_year(j,r,y,z)=minF+(y-Fstartyr)*stepF*mfexp(F_RN(j,r,y,z)*sigma_F(j,r,z)-0.5*square(sigma_F(j,r,z)));
                }
               }
               if(y>=((nyrs-Fstartyr)/2+Fstartyr))
                {
                 F_year(j,r,y,z)=maxF-((y-Fstartyr)-((nyrs-Fstartyr)/2))*stepF*mfexp(F_RN(j,r,y,z)*sigma_F(j,r,z)-0.5*square(sigma_F(j,r,z)));
                  if(F_year(j,r,y,z)<0) //needed because the stepF decrease can be randomly be greater than preceding F, and so F goes negative
                  {
                  F_year(j,r,y,z)=minF;
                  }
                }
              }
             F_fleet(j,r,y,a,z)=F_year(j,r,y,z)*selectivity(j,r,y,a,z);
             F(j,r,y,a)=sum(F_fleet(j,r,y,a)); 
             M(j,r,y,a)=input_M(j,a);
           }
          }
         }
        }
       }
FUNCTION get_vitals
//POSSIBLE ADDITIONS:
  //random walk in apportionment or random to give time-varying
  //switch for input recruitment devs by year to recreate a given population trajectory

  for (int p=1;p<=npops;p++)
   {
    for (int j=1;j<=npops;j++)
     {  
      for (int r=1;r<=nregions(j);r++)   
       {       
        for (int y=1;y<=nyrs;y++)
         {
          for (int a=1;a<=nages;a++)
           {
            for (int z=1;z<=nfleets(j);z++)
             {
              weight_population(j,r,y,a)=input_weight(j,r,a);
              weight_catch(j,r,y,a)=input_catch_weight(j,r,a);

              if(maturity_switch_equil==0) // for SPR calculations when maturity across areas is equal or if want a straight average of maturity across areas
               {
                if(SSB_type==1) //fecundity based SSB
                 {
                  ave_mat_temp(j,a,r)=prop_fem(j,r)*fecundity(j,r,a)*maturity(j,r,a);//rearranging for summing
                  ave_mat(j,a) = sum(ave_mat_temp(j,a))/nregions(j); //average maturity across regions
                  wt_mat_mult(j,y,a)=ave_mat(j,a);//for SPR calcs
                 }
               if(SSB_type==2) //weight based SSB
                {
                  ave_mat_temp(j,a,r)=prop_fem(j,r)*weight_population(j,r,y,a)*maturity(j,r,a);//rearranging for summing
                  ave_mat(j,a) = sum(ave_mat_temp(j,a))/nregions(j); //average maturity across regions
                  wt_mat_mult(j,y,a)=ave_mat(j,a);//for SPR calcs
                }
               }
              if(maturity_switch_equil==1)
               {// calculates the weighted average matruity based on equilibrium apportionment of SSB - allows for unequal influence of maturity/weight
                if(SSB_type==1) //fecundity based SSB
                 {
                  ave_mat_temp(j,a,r)=prop_fem(j,r)*fecundity(j,r,a)*maturity(j,r,a)*equil_ssb_apport(j,r);//rearranging for summing
                  ave_mat(j,a) = sum(ave_mat_temp(j,a))/nregions(j); //average maturity across regions
                  wt_mat_mult(j,y,a)=ave_mat(j,a);//for SPR calcs
                 }
               if(SSB_type==2) //weight based SSB
                {
                  ave_mat_temp(j,a,r)=prop_fem(j,r)*weight_population(j,r,y,a)*maturity(j,r,a);//rearranging for summing
                  ave_mat(j,a) = sum(ave_mat_temp(j,a))/nregions(j); //average maturity across regions
                  wt_mat_mult(j,y,a)=ave_mat(j,a);//for SPR calcs
                }
               }                        
               if(recruit_devs_switch==0)  //use population recruit relationship directly
                {
                 rec_devs(j,y)=1;
                }
               if(recruit_devs_switch==1)  // allow lognormal error around SR curve
                {
                 rec_devs(j,y)=mfexp(rec_devs_RN(j,y)*sigma_recruit(j)-.5*square(sigma_recruit(j)));

                 if(recruit_randwalk_switch==1)
                 {
                  rec_devs_randwalk(j,y)=rec_devs(j,y);
                  if(y!=1)
                   {
                    rec_devs(j,y)=rec_devs(j,y-1)*rec_devs_randwalk(j,y);
                   }
                 }
                }
               if(SSB_type==1) //fecundity based SSB
                {
                 wt_mat_mult_reg(j,r,y,a)=prop_fem(j,r)*fecundity(j,r,a)*maturity(j,r,a);// for yearly SSB calcs
                }
               if(SSB_type==2) //weight based SSB
                {
                 wt_mat_mult_reg(j,r,y,a)=prop_fem(j,r)*weight_population(j,r,y,a)*maturity(j,r,a);
                }
               if(apportionment_type==1) //input recruitment apportionment directly by population and region
                {
                 Rec_Prop(j,r,y)=input_Rec_prop(j,r);
                }
               if(apportionment_type==2) //equal apportionment by nregions
                {
               Rec_Prop(j,r,y)=1.0/nregions(j);
                }
               if(apportionment_type==(-1)) // no apportionment
                {
                 Rec_Prop(j,r,y)=1;
                }
               if(apportionment_type==3)//completely random apportionment
                {
                Rec_prop_temp1(j,y,r)=Rec_apport_RN(j,y,r);//generate a positive random number bw 0-1
                }                 
               if(apportionment_type==4) //add input obersvation error to input recruit proportions following Schnute and Richards 1995 (as implemented in Cox and Kronlund 2008)
                {
                 Rec_prop_temp1(j,y,r)=log(input_Rec_prop(j,r))+sigma_rec_prop(j)*Rec_apport_RN(j,y,r);//applying the additive error in log space; this equals "log(u) + error" in Cox and Kronlund Table 1
                }
               //if(apportionment_type==5)    /// add in the two switches for shifting approtionment based on the enviromment. and random with normal dis
               }   
             }
           }         
         }

  for (int r=1;r<=nregions(j);r++)
       {
        for (int y=1;y<=nyrs;y++)
         {
          if(apportionment_type==3)
           { //need to standardize year by region matrix to ensure new proportions sum to one
            Rec_Prop(j,r,y)=Rec_prop_temp1(j,y,r)/sum(Rec_prop_temp1(j,y));
           }
          if(apportionment_type==4)
           { //need to run through region by year matrix to calculate second half of Schnute and Richards 1995 random mult equations and to standardize randomized apportioments to total one
            Rec_prop_temp2(j,y,r)=Rec_prop_temp1(j,y,r)-(sum(Rec_prop_temp1(j,y))/nregions(j)); //finish equation T1.21 in Cox and Kronlund Table 1 (note that here nregions is the same as A (number of ages) in Table 1 paper
            Rec_Prop(j,r,y)=mfexp(Rec_prop_temp2(j,y,r))/sum(mfexp(Rec_prop_temp2(j,y))); // back-transform and standardize
           }
         }
        }
       }
     }

//SPR calcs are done with eitehr  average maturity/weight across all the regions within a population or assuming an input population fraction at equilibrium
// while the full SSB calcs use the region specific maturity/weight
FUNCTION get_SPR
      for (int k=1;k<=npops;k++)
     {
      for (int n=1;n<=nages;n++)
       {
        if(n==1)
         {
          SPR_N(k,n)=1000;
          SPR_SSB(k,n)=wt_mat_mult(k,1,n)*SPR_N(k,n);
         }
        if(n>1 && n<nages)
         {
          SPR_N(k,n)=SPR_N(k,n-1)*mfexp(-M(k,1,1,n-1));
          SPR_SSB(k,n)=wt_mat_mult(k,1,n)*SPR_N(k,n);
         }
        if(n==nages)
         {
          SPR_N(k,n)=SPR_N(k,n-1)*mfexp(-M(k,1,1,n))*(1/(1-mfexp(-M(k,1,1,n))));
          SPR_SSB(k,n)=wt_mat_mult(k,1,n)*SPR_N(k,n);
         }
       }
     SPR(k)=sum(SPR_SSB(k))/1000;
     SSB_zero(k)=SPR(k)*R_ave(k);
      if(Rec_type==2) //BH recruitment
      {
      //alpha(k)=SPR(k)*(1-steep(k))/(4*steep(k));
      alpha(k)=(SSB_zero(k)/R_ave(k))*((1-steep(k))/(4*steep(k)));//alternate parameterization
      beta(k)=(5*steep(k)-1)/(4*steep(k)*R_ave(k));
      }
    }

FUNCTION get_env_Rec // calculate autocorrelated recruitment - input period and amplitude
       for (int p=1;p<=npops;p++)
        {
        for (int j=1;j<=npops;j++)
         {
         for (int r=1;r<=nregions(j);r++)
          {
          for (int y=1;y<=nyrs;y++)
           {
           if(y==1)
             {
              env_rec(y)=init_abund(p,j,r,1);
             }           
           if(y>1)
            {
             env_rec(y) = R_ave(j)+(R_ave(j)*amplitude)*sin(((2*M_PI)/freq)*years(y)+freq);
            }
           }
         }
        }
       }
FUNCTION get_DD_move_parameters
 //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
 ///////////////////////DD Movement///////////////////////////////////////////////////////////////////////////////////////////////////
           /// rel_bio gives ratio of biomass in each area weighted by ratio to Bstar, use 1-ratio of bio
            /// because want to weight T and make more fish move to area with lower bio compared to Bstar
            /// idea is that if B/Bstar<1 then not densely populated and more fish would move there           
      if(move_switch==8)
       {
        for (int s=1;s<=npops;s++)
         {
          for (int n=1;n<=nregions(s);n++)
           {       
            if(use_input_Bstar==0 && Rec_type==2) //set Bstar==SSB0
             {
              if(nregions(s)==1)
               {
                Bstar(s,n)=SSB_zero(s);
               }
              if(nregions(s)>1)
               {
                Bstar(s,n)=SSB_zero(s)*SSB_zero_appor(s,n);
               }
             }
            if(use_input_Bstar==1 || Rec_type!=2)
             {
              Bstar(s,n)=input_Bstar(s,n);
             }
           c(s,n)=-log(A(s,n))/Bstar(s,n);  ///Bstar is the point of inflection in T
          }
         }
        }

FUNCTION get_abundance
       for (int y=1;y<=nyrs;y++)
        {

//need to add all_natal calcs for all values that might want to compare across an area, because regular non-natal homing calcs do not account for different weights across natal populationp so if if any part of calc involves weight it needs to use the biomass_all_natal value not just biomass_AM

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////// Y==1 Overlap Calcs ///////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

       if(y==1)
         {
         for (int a=1;a<=nages;a++)
          {
           for (int p=1;p<=npops;p++)
            {
             for (int j=1;j<=npops;j++)
              {
               for (int r=1;r<=nregions(j);r++)
                {
                 for (int z=1;z<=nfleets(j);z++)
                  {
                    abundance_at_age_BM_overlap_region(p,j,y,a,r)=init_abund(p,j,r,a);
                    abundance_at_age_BM_overlap_population(p,j,y,a)=sum(abundance_at_age_BM_overlap_region(p,j,y,a));
                    biomass_BM_age_overlap(p,j,r,y,a)=weight_population(p,r,y,a)*abundance_at_age_BM_overlap_region(p,j,y,a,r);
                    biomass_BM_overlap_region(p,j,r,y)=sum(biomass_BM_age_overlap(p,j,r,y));

//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
///////////////NON-NATAL Homing calcs /////////////////////////////////////////////////////////////// //////////////////////////////////////////////////////////////////////////////    
                   init_abund_temp(j,r,a,p)=init_abund(p,j,r,a);
                   abundance_at_age_BM(j,r,y,a)=sum(init_abund_temp(j,r,a));
                   recruits_BM(j,r,y)=abundance_at_age_BM(j,r,y,1);
////////////////////////////////////////////////////////////////////////////////

                  if(natal_homing_switch==0)
                   {
                    biomass_BM_age(j,r,y,a)=weight_population(j,r,y,a)*abundance_at_age_BM(j,r,y,a);
                    biomass_BM(j,r,y)=sum(biomass_BM_age(j,r,y));
                   }
                  if(natal_homing_switch>0) //if natal homing put abundance summed across natal population by region into abundance at age AM
                   {
                    biomass_BM_overlap_temp(j,r,y,a,p)=biomass_BM_age_overlap(p,j,r,y,a);
                    biomass_BM_age(j,r,y,a)=sum(biomass_BM_overlap_temp(j,r,y,a));
                    biomass_BM(j,r,y)=sum(biomass_BM_age(j,r,y));
                   }
                   
 ///get year one recruitment index
               rec_index_BM(j,r,y) = recruits_BM(j,r,y)*mfexp(rec_index_RN(j,r,y)*rec_index_sigma(j,r)-0.5*square(rec_index_sigma(j,r)));
               rec_index_BM_temp(j,y,r)=rec_index_BM(j,r,y);
               rec_index_prop_BM(j,r,y)=rec_index_BM(j,r,y)/sum(rec_index_BM_temp(j,y));
              }
             }
            }
           }
          } //close loops so have full biomass vectors filled in at start of DD movement calcs

         for (int a=1;a<=nages;a++)
          {
           for (int p=1;p<=npops;p++)
            {
             for (int j=1;j<=npops;j++)
              {
               for (int r=1;r<=nregions(j);r++)
                {
                 for (int z=1;z<=nfleets(j);z++)
                  {

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////Density-Dependent Movement Calcs///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
           /// rel_bio gives ratio of biomass in each area weighted by ratio to Bstar, use 1-ratio of bio
            /// because want to weight T and make more fish move to area with lower bio compared to Bstar
            /// idea is that if B/Bstar<1 then not densely populated and more fish would move there
            
                    if(move_switch==8)
                     {
                      Fract_Move_DD(j,r,y,a)=(1-input_residency(j,r,a))/(1+A(j,r)*mfexp(c(j,r)*biomass_BM_age(j,r,y,a)));
       
                      biomass_BM_temp=0;
                      biomass_BM_temp2=0;
                       for (int s=1;s<=npops;s++)
                        {
                         for (int n=1;n<=nregions(s);n++)
                          {       
                           biomass_BM_temp(s,n)=biomass_BM_age(s,n,y,a)/Bstar(s,n);
                          }
                        }
                       biomass_BM_temp2=sum(biomass_BM_temp)-(biomass_BM_age(j,r,y,a)/Bstar(j,r)); //do not include population/region moving from in summation
                        for (int s=1;s<=npops;s++)
                         {
                          for (int n=1;n<=nregions(s);n++)
                           {
                            if(j==s && r==n) //do not include current pop/region in calcs (residency is already defined)
                             {
                              rel_bio(j,r,y,a,s,n)=0;  //rel bio defined for movement out of pop j region r as suitability of destination population s, region n
                             }
                            if(j!=s || r!=n) 
                             {
                              rel_bio(j,r,y,a,s,n)=1-((biomass_BM_temp(s,n))/(biomass_BM_temp2));
                             }
                            if(sum(nregions)==2)
                             {
                              rel_bio(j,r,y,a,s,n)=1;
                             }
                            }
                           }                          
                       for (int s=1;s<=npops;s++)
                        {
                         for (int n=1;n<=nregions(s);n++)
                          {
                           if(j==s && r==n) 
                            {
                             T(j,r,y,a,s,n)=1-Fract_Move_DD(j,r,y,a);
                            }
                           if(j!=s || r!=n) 
                            {
                             T(j,r,y,a,s,n)=rel_bio(j,r,y,a,s,n)*Fract_Move_DD(j,r,y,a);
                            }
                          }
                        }
                    }
                  
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

                abundance_move_overlap_temp=0;

                for (int k=1;k<=npops;k++)
                 {
                  for (int n=1;n<=nregions(k);n++)
                   {              
                    if(move_switch!=6 || move_switch!=7 || a==1)  //if movement is not type=6 or a==1 (and movement type 6)
                     {
                       abundance_move_overlap_temp(k,n)=init_abund(p,k,n,a)*T(p,n,y,a,j,r); //with overlap always use natal population movement rates  (i.e., use p inpsead of k)
                     }
                    if(move_switch==6 && a>1)
                     {
                      if(a==return_age && p==j && p==k && j==k)
                      {
                       abundance_move_overlap_temp(k,n)=0; //with overlap always use natal population movement rates
                      }
                      if(a==return_age && p==j && j!=k)
                      {
                       abundance_move_overlap_temp(k,n)=init_abund(p,k,n,a)*return_probability(p); //with overlap always use natal population movement rates
                      }
                     }
                   }
                  }
                    if(move_switch!=6 || move_switch!=7  || a==1)
                     {
                        abundance_at_age_AM_overlap_region(p,j,y,a,r)=sum(abundance_move_overlap_temp);
                     }
                    if(move_switch==7)  //all fish stay where they were (i.e., no return migration)
                     {
                        abundance_at_age_AM_overlap_region(p,j,y,a,r)=init_abund(p,j,r,a);
                     }
                    if(move_switch==6 && a>1)
                     {
                      if(a<return_age || a>return_age)
                       {
                        abundance_at_age_AM_overlap_region(p,j,y,a,r)=init_abund(p,j,r,a); //with overlap always use natal population movement rates                     
                       }
                      if(a==return_age && p==j)
                       {
                        abundance_at_age_AM_overlap_region(p,j,y,a,r)=init_abund(p,j,r,a)+(sum(abundance_move_overlap_temp)/nregions(p));
                       }
                      if(a==return_age && p!=j)
                       {
                        abundance_at_age_AM_overlap_region(p,j,y,a,r)=(1-return_probability(p))*init_abund(p,j,r,a);
                       }
                      }
                      
                abundance_AM_overlap_region_all_natal_temp(j,r,y,a,p)=abundance_at_age_AM_overlap_region(p,j,y,a,r);
                biomass_AM_overlap_region_all_natal_temp(j,r,y,a,p)=abundance_at_age_AM_overlap_region(p,j,y,a,r)*weight_population(p,r,y,a);
                abundance_AM_overlap_region_all_natal(j,r,y,a)=sum(abundance_AM_overlap_region_all_natal_temp(j,r,y,a));
                biomass_AM_overlap_age_region_all_natal(j,r,y,a)=sum(biomass_AM_overlap_region_all_natal_temp(j,r,y,a));
                biomass_AM_overlap_region_all_natal(j,r,y)=sum(biomass_AM_overlap_age_region_all_natal(j,r,y));
                abundance_at_age_AM_overlap_population(p,j,y,a)=sum(abundance_at_age_AM_overlap_region(p,j,y,a));
                biomass_AM_age_overlap(p,j,r,y,a)=weight_population(p,r,y,a)*abundance_at_age_AM_overlap_region(p,j,y,a,r);
                biomass_AM_overlap_region(p,j,r,y)=sum(biomass_AM_age_overlap(p,j,r,y));
                biomass_population_temp_overlap(p,j,y,r)=biomass_AM_overlap_region(p,j,r,y);
                biomass_population_overlap(p,j,y)=sum(biomass_population_temp_overlap(p,j,y));
                biomass_natal_temp_overlap(p,y,j)=biomass_population_overlap(p,j,y);
                biomass_natal_overlap(p,y)=sum(biomass_natal_temp_overlap(p,y));

///////////MIGHT WANT TO DO FOLLOWING CALCS FOR NATAL HOMING AS WELL (DO METAPOP TYPE CALCS BELOW)
              //  abundance_in(j,r,y,a)=sum(abundance_move_temp)-abundance_move_temp(j,r);
              //  abundance_res(j,r,y,a)=abundance_move_temp(j,r);
              //  abundance_leave(j,r,y,a)=abundance_at_age_BM(j,r,y,a)-abundance_res(j,r,y,a);
              //  bio_in(j,r,y,a)=sum(bio_move_temp)-bio_move_temp(j,r);
              //  bio_res(j,r,y,a)=bio_move_temp(j,r);
              //  bio_leave(j,r,y,a)=abundance_at_age_BM(j,r,y,a)*weight_population(j,y,a)-bio_res(j,r,y,a);
                
//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
///////////////NON-NATAL Homing movement calcs and putting natal homing abundance into area abundance/////////////////////////////////////////////////////////////// //////////////////////////////////////////////////////////////////////////////
    
                abundance_move_temp=0;
                bio_move_temp=0;

                for (int k=1;k<=npops;k++)
                 {
                  for (int n=1;n<=nregions(k);n++)
                   {
                     abundance_move_temp(k,n)=abundance_at_age_BM(k,n,y,a)*T(k,n,y,a,j,r);
                     bio_move_temp(k,n)=abundance_move_temp(k,n)*weight_population(k,n,y,a);                   
                   }
                  }
                  if(natal_homing_switch>0) //if natal homing put abundance summed across natal population by region into abundance at age AM
                   {
                    abundance_at_age_AM(j,r,y,a)=abundance_AM_overlap_region_all_natal(j,r,y,a);
                    biomass_AM(j,r,y)= biomass_AM_overlap_region_all_natal(j,r,y);
                   }
                  if(natal_homing_switch==0)
                   {
                    abundance_at_age_AM(j,r,y,a)=sum(abundance_move_temp);
                    biomass_AM_age(j,r,y,a)=weight_population(j,r,y,a)*abundance_at_age_AM(j,r,y,a);
                    biomass_AM(j,r,y)=sum(biomass_AM_age(j,r,y));
                   }
                   
                abundance_population_temp(j,y,a,r)=abundance_at_age_AM(j,r,y,a);
                abundance_population(j,y,a)=sum(abundance_population_temp(j,y,a));
                abundance_total_temp(y,a,j)=abundance_population(j,y,a);
                abundance_total(y,a)=sum(abundance_total_temp(y,a));
                biomass_population_temp(j,y,r)=biomass_AM(j,r,y);
                biomass_population(j,y)=sum(biomass_population_temp(j,y));
                biomass_total_temp(y,j)=biomass_population(j,y);
                biomass_total(y)=sum(biomass_total_temp(y));

                recruits_AM(j,r,y)=abundance_at_age_AM(j,r,y,a);                
                rec_index_AM(j,r,y)=recruits_AM(j,r,y)*mfexp(rec_index_RN(j,r,y)*rec_index_sigma(j,r)-0.5*square(rec_index_sigma(j,r)));
                rec_index_AM_temp(j,y,r)=rec_index_AM(j,r,y);
                rec_index_prop_AM(j,r,y)=rec_index_AM(j,r,y)/sum(rec_index_AM_temp(j,y));

                abundance_in(j,r,y,a)=sum(abundance_move_temp)-abundance_move_temp(j,r);
                abundance_res(j,r,y,a)=abundance_move_temp(j,r);
                abundance_leave(j,r,y,a)=abundance_at_age_BM(j,r,y,a)-abundance_res(j,r,y,a);
                bio_in(j,r,y,a)=sum(bio_move_temp)-bio_move_temp(j,r);
                bio_res(j,r,y,a)=bio_move_temp(j,r);
                bio_leave(j,r,y,a)=abundance_at_age_BM(j,r,y,a)*weight_population(j,r,y,a)-bio_res(j,r,y,a);
    
          } //end fleets loop

             for (int z=1;z<=nfleets_survey(j);z++)    /// survey index  1. Currently set up for more than 1 survey fleet
              {
               if(tsurvey(j,r)==0) //if survey at beggining of year, do calcs without temporal adjustment for mortality
                {
                  true_survey_fleet_overlap_age(p,j,r,y,z,a)=survey_selectivity(j,r,y,a,z)*abundance_at_age_AM_overlap_region(p,j,y,a,r)*q_survey(j,r,z);
                  true_survey_fleet_overlap_age_bio(p,j,r,y,z,a)=true_survey_fleet_overlap_age(p,j,r,y,z,a)*weight_population(p,r,y,a);
                  true_survey_fleet_bio_overlap(p,j,r,y,z)=sum(true_survey_fleet_overlap_age_bio(p,j,r,y,z));  
                  true_survey_fleet_bio_overlap_temp(j,r,y,z,p)=true_survey_fleet_bio_overlap(p,j,r,y,z);
                  OBS_survey_fleet_bio_overlap(p,j,r,y,z)=true_survey_fleet_bio_overlap(p,j,r,y,z)*mfexp(survey_RN_overlap(p,j,r,y,z)*sigma_survey_overlap(p,j,r,z)-.5*square(sigma_survey_overlap(p,j,r,z)));
                  OBS_survey_fleet_bio_temp(j,r,y,z,p)=OBS_survey_fleet_bio_overlap(p,j,r,y,z);

                if(natal_homing_switch==0)
                 {
                  true_survey_fleet_age(j,r,y,z,a)=survey_selectivity(j,r,y,a,z)*abundance_at_age_AM(j,r,y,a)*q_survey(j,r,z);
                  true_survey_fleet_age_bio(j,r,y,z,a)=true_survey_fleet_age(j,r,y,z,a)*weight_population(j,r,y,a);                  
                  true_survey_fleet_bio(j,r,y,z)=sum(true_survey_fleet_age_bio(j,r,y,z));
                  OBS_survey_fleet_bio(j,r,y,z)=true_survey_fleet_bio(j,r,y,z)*mfexp(survey_RN(j,r,y,z)*sigma_survey(j,r,z)-.5*square(sigma_survey(j,r,z)));
                 }
                if(natal_homing_switch==1)
                 {
                  true_survey_fleet_bio(j,r,y,z)=sum(true_survey_fleet_bio_overlap_temp(j,r,y,z));
                  OBS_survey_fleet_bio(j,r,y,z)=sum(OBS_survey_fleet_bio_temp(j,r,y,z));  
                 }
             
                  true_survey_region_bio_overlap(p,j,y,r)=sum(true_survey_fleet_bio_overlap(p,j,r,y));               
                  true_survey_population_bio_overlap(p,y,j)=sum(true_survey_region_bio_overlap(p,j,y));               
                  true_survey_natal_bio_overlap(y,p)=sum(true_survey_population_bio_overlap(p,y));               
                  true_survey_total_bio_overlap(y)=sum(true_survey_natal_bio_overlap(y));
                  OBS_survey_region_bio_overlap(p,j,y,r)=sum(OBS_survey_fleet_bio_overlap(p,j,r,y));
                  OBS_survey_population_bio_overlap(p,y,j)=sum(OBS_survey_region_bio_overlap(p,j,y));
                  OBS_survey_natal_bio_overlap(y,p)=sum(OBS_survey_population_bio_overlap(p,y));
                  OBS_survey_total_bio_overlap(y)=sum(OBS_survey_natal_bio_overlap(y));
                  
                  true_survey_region_bio(j,y,r)=sum(true_survey_fleet_bio(j,r,y));
                  true_survey_population_bio(y,j)=sum(true_survey_region_bio(j,y));
                  true_survey_total_bio(y)=sum(true_survey_population_bio(y));
                  OBS_survey_region_bio(j,y,r)=sum(OBS_survey_fleet_bio(j,r,y));
                  OBS_survey_population_bio(y,j)=sum(OBS_survey_region_bio(j,y));
                  OBS_survey_total_bio(y)=sum(OBS_survey_population_bio(y));

                  apport_region_survey_biomass(j,r,y)=OBS_survey_region_bio(j,y,r)/OBS_survey_population_bio(y,j);
                  
                }  //tsurvey==0
               } //end survey_fleets
            }
           }
          }
         } //end age loop
 ///////////////////////////////////////////////////////////////////////////////////
 ////////////////NEWTON-RAPHSON for YEAR 1////////////////////////////////////////////////////////////////////////////
 //////////////////////////////////////////////////////////////////////////////////////////////////////
           for (int p=1;p<=npops;p++)
            {
             for (int j=1;j<=npops;j++)
              {
               for (int r=1;r<=nregions(j);r++)
                {
                   if(model_type_switch>0)  //Find the fully selected F that would result in the TAC
                     {
                      for (int a=1;a<=nages;a++)
                       {
                         for(int x=1;x<=nfleets(j);x++)
                           {
                             if(model_type_switch==1)
                                {
                                 if(natal_homing_switch>0)
                                   {
                                               if(parse_TAC==0) //use input TAC
                                                {
                                                  if(calc_TAC_from_uMSY==0)
                                                   {
                                                    TAC(j,r,x,y)=input_TAC(j,r,x);
                                                   }
                                                   if(calc_TAC_from_uMSY==1)
                                                   {
                                                    TAC(j,r,x,y)=input_u(j,r,x)*biomass_population(j,y);
                                                   }
                                                   if(calc_TAC_from_uMSY==2)
                                                   {
                                                    TAC(j,r,x,y)=input_u(j,r,x)*biomass_AM(j,r,y);
                                                   }
                                                }
                                             if(parse_TAC==1) //use observed data to parse input_TAC by region // if multiple fleets then evenly distribute across fleets
                                                {
                                                 if(parse_TAC_source==0)
                                                  {
                                                  if(calc_TAC_from_uMSY==0)
                                                   {
                                                   if(y==1)
                                                    {
                                                     TAC(j,r,x,y)=input_TAC(j,r,x)/(nregions(j)*nfleets(j)); //partition evenly by total fleets in area
                                                    }
                                                   if(y>1) //assume rec index occurs at time of spawning so never have available in current year
                                                    {
                                                     TAC(j,r,x,y)=rec_index_prop_BM(j,r,y-1)*input_TAC(j,r,x)/nfleets(j); //partition regional quota evenly by fleets in region
                                                    }
                                                   }
                                                  if(calc_TAC_from_uMSY==1)
                                                   {
                                                   if(y==1)
                                                    {
                                                     TAC(j,r,x,y)=input_u(j,r,x)*biomass_population(j,y)/(nregions(j)*nfleets(j)); //partition evenly by total fleets in area
                                                    }
                                                   if(y>1) //assume rec index occurs at time of spawning so never have available in current year
                                                    {
                                                     TAC(j,r,x,y)=rec_index_prop_BM(j,r,y-1)*input_u(j,r,x)*biomass_population(j,y)/nfleets(j); //partition regional quota evenly by fleets in region
                                                    }
                                                   }
                                                  if(calc_TAC_from_uMSY==2)
                                                   {
                                                   if(y==1)
                                                    {
                                                     TAC(j,r,x,y)=input_u(j,r,x)*biomass_AM(j,r,y)/(nregions(j)*nfleets(j)); //partition evenly by total fleets in area
                                                    }
                                                   if(y>1) //assume rec index occurs at time of spawning so never have available in current year
                                                    {
                                                     TAC(j,r,x,y)=rec_index_prop_BM(j,r,y-1)*input_u(j,r,x)*biomass_AM(j,r,y)/nfleets(j); //partition regional quota evenly by fleets in region
                                                    }
                                                   }
                                                  }
                                                 if(parse_TAC_source==1)
                                                  {
                                                  if(calc_TAC_from_uMSY==0)
                                                   {
                                                   if(y==1)
                                                    {
                                                     TAC(j,r,x,y)=input_TAC(j,r,x)/(nregions(j)*nfleets(j)); //partition evenly by total fleets in area
                                                    }
                                                   if(y>1) //assume rec index occurs at time of spawning so never have available in current year
                                                    {
                                                     TAC(j,r,x,y)=rec_index_prop_AM(j,r,y-1)*input_TAC(j,r,x)/nfleets(j); //partition regional quota evenly by fleets in region
                                                    }
                                                   }
                                                  if(calc_TAC_from_uMSY==1)
                                                   {
                                                   if(y==1)
                                                    {
                                                     TAC(j,r,x,y)=input_u(j,r,x)*biomass_population(j,y)/(nregions(j)*nfleets(j)); //partition evenly by total fleets in area
                                                    }
                                                   if(y>1) //assume rec index occurs at time of spawning so never have available in current year
                                                    {
                                                     TAC(j,r,x,y)=rec_index_prop_AM(j,r,y-1)*input_u(j,r,x)*biomass_population(j,y)/nfleets(j); //partition regional quota evenly by fleets in region
                                                    }
                                                   }
                                                  if(calc_TAC_from_uMSY==2)
                                                   {
                                                   if(y==1)
                                                    {
                                                     TAC(j,r,x,y)=input_u(j,r,x)*biomass_AM(j,r,y)/(nregions(j)*nfleets(j)); //partition evenly by total fleets in area
                                                    }
                                                   if(y>1) //assume rec index occurs at time of spawning so never have available in current year
                                                    {
                                                     TAC(j,r,x,y)=rec_index_prop_AM(j,r,y-1)*input_u(j,r,x)*biomass_AM(j,r,y)/nfleets(j); //partition regional quota evenly by fleets in region
                                                    }
                                                   }
                                                  }
                                                 if(parse_TAC_source==2)
                                                  {
                                                  if(calc_TAC_from_uMSY==0)
                                                   {
                                                   if(TAC_survey_parse_timelag_switch==1) //use timelag
                                                    {
                                                       if(y<=TAC_survey_parse_timelag) //apportion TAC equally among fleets if y<timelag
                                                        {                                                     
                                                         TAC(j,r,x,y)=input_TAC(j,r,x)/(nregions(j)*nfleets(j));
                                                        }
                                                       if(y>TAC_survey_parse_timelag)
                                                        {                                                     
                                                         TAC(j,r,x,y)=apport_region_survey_biomass(j,r,(y-TAC_survey_parse_timelag))*input_TAC(j,r,x)/nfleets(j);
                                                        }
                                                     }
                                                  if(TAC_survey_parse_timelag_switch==0) //no timelag
                                                    {
                                                     if(tsurvey(j,r)==0)
                                                      {
                                                       TAC(j,r,x,y)=apport_region_survey_biomass(j,r,y)*input_TAC(j,r,x)/nfleets(j);
                                                      }
                                                     if(tsurvey(j,r)>0)
                                                      {
                                                       if(y==1) //first year apportion TAC equally among fleets
                                                        {                                                     
                                                         TAC(j,r,x,y)=input_TAC(j,r,x)/(nregions(j)*nfleets(j));
                                                        }
                                                       if(y>1)
                                                        {                                                     
                                                         TAC(j,r,x,y)=apport_region_survey_biomass(j,r,y-1)*input_TAC(j,r,x)/nfleets(j);
                                                        }
                                                       }
                                                     }
                                                    }
                                                  if(calc_TAC_from_uMSY==1)
                                                   {
                                                   if(TAC_survey_parse_timelag_switch==1) //use timelag
                                                    {
                                                       if(y<=TAC_survey_parse_timelag)
                                                        {                                                     
                                                         TAC(j,r,x,y)=input_u(j,r,x)*biomass_population(j,y)/(nregions(j)*nfleets(j));
                                                        }
                                                       if(y>TAC_survey_parse_timelag)
                                                        {                                                     
                                                         TAC(j,r,x,y)=apport_region_survey_biomass(j,r,(y-TAC_survey_parse_timelag))*input_u(j,r,x)*biomass_population(j,y)/nfleets(j);
                                                        }
                                                     }
                                                  if(TAC_survey_parse_timelag_switch==0) //no timelag
                                                    {
                                                     if(tsurvey(j,r)==0)
                                                      {
                                                       TAC(j,r,x,y)=apport_region_survey_biomass(j,r,y)*input_u(j,r,x)*biomass_population(j,y)/nfleets(j);
                                                      }
                                                     if(tsurvey(j,r)>0)
                                                      {
                                                       if(y==1) //first year apportion TAC equally among fleets
                                                        {                                                     
                                                         TAC(j,r,x,y)=input_u(j,r,x)*biomass_population(j,y)/(nregions(j)*nfleets(j));
                                                        }
                                                       if(y>1)
                                                        {                                                     
                                                         TAC(j,r,x,y)=apport_region_survey_biomass(j,r,y-1)*input_u(j,r,x)*biomass_population(j,y)/nfleets(j);
                                                        }
                                                       }
                                                     }
                                                    }
                                                  if(calc_TAC_from_uMSY==2)
                                                   {
                                                   if(TAC_survey_parse_timelag_switch==1) //use timelag
                                                    {
                                                       if(y<=TAC_survey_parse_timelag)
                                                        {                                                     
                                                         TAC(j,r,x,y)=input_u(j,r,x)*biomass_AM(j,r,y)/(nregions(j)*nfleets(j));
                                                        }
                                                       if(y>TAC_survey_parse_timelag)
                                                        {                                                     
                                                         TAC(j,r,x,y)=apport_region_survey_biomass(j,r,(y-TAC_survey_parse_timelag))*input_u(j,r,x)*biomass_AM(j,r,y)/nfleets(j);
                                                        }
                                                     }
                                                  if(TAC_survey_parse_timelag_switch==0) //no timelag
                                                    {
                                                     if(tsurvey(j,r)==0)
                                                      {
                                                       TAC(j,r,x,y)=apport_region_survey_biomass(j,r,y)*input_u(j,r,x)*biomass_AM(j,r,y)/nfleets(j);
                                                      }
                                                     if(tsurvey(j,r)>0)
                                                      {
                                                       if(y==1) //first year apportion TAC equally among fleets
                                                        {                                                     
                                                         TAC(j,r,x,y)=input_u(j,r,x)*biomass_AM(j,r,y)/(nregions(j)*nfleets(j));
                                                        }
                                                       if(y>1)
                                                        {                                                     
                                                         TAC(j,r,x,y)=apport_region_survey_biomass(j,r,y-1)*input_u(j,r,x)*biomass_AM(j,r,y)/nfleets(j);
                                                        }
                                                       }
                                                     }
                                                    }
                                                   }
                                                 if(parse_TAC_source==3)
                                                  {
                                                  if(calc_TAC_from_uMSY==0)
                                                   {
                                                    TAC(j,r,x,y)=input_TAC(j,r,x)/(nregions(j)*nfleets(j));
                                                   }
                                                  if(calc_TAC_from_uMSY==1)
                                                   {
                                                    TAC(j,r,x,y)=input_u(j,r,x)*biomass_population(j,y)/(nregions(j)*nfleets(j));
                                                   }
                                                  if(calc_TAC_from_uMSY==2)
                                                   {
                                                    TAC(j,r,x,y)=input_u(j,r,x)*biomass_AM(j,r,y)/(nregions(j)*nfleets(j));
                                                   }
                                                  }
                                                 }
                                     if(TAC(j,r,x,y)==0) //iterationp have trouble finding F=0 when target=0; but they work great for >0 values.  This prevents those issues
                                       {
                                        Fnew=0;
                                       }
                                     if(TAC(j,r,x,y)>0) //iterationp have trouble finding F=0 when target=0; but they work great for >0 values.  This prevents those issues
                                      {
                                        Fnew=Fnew_start;
                                        for(int i=1;i<=NR_iterationp;i++)  //newton-raphson iterationp
                                         {
                                          delt=Fnew*NR_dev;  // NR_dev~0.001
                                           for(int s=1;s<=nages;s++)
                                             {
                                              if(s==1)
                                               {
                                                 fofFvect(s)=((Fnew*selectivity(j,r,y,s,x))/(Fnew*selectivity(j,r,y,s,x)+M(j,r,y,s)))*biomass_AM_overlap_age_region_all_natal(j,r,y,s)*(1-mfexp(-1*(Fnew*selectivity(j,r,y,s,x)+M(j,r,y,s))*(1-tspawn(j))));
                                                 fprimeFhigh(s)=(((Fnew+delt)*selectivity(j,r,y,s,x))/((Fnew+delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))*biomass_AM_overlap_age_region_all_natal(j,r,y,s)*(1-mfexp(-1*((Fnew+delt)*selectivity(j,r,y,s,x)+M(j,r,y,s))*(1-tspawn(j))));
                                                 fprimeFlow(s)=(((Fnew-delt)*selectivity(j,r,y,s,x))/((Fnew-delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))*biomass_AM_overlap_age_region_all_natal(j,r,y,s)*(1-mfexp(-1*((Fnew-delt)*selectivity(j,r,y,s,x)+M(j,r,y,s))*(1-tspawn(j))));                                              
                                               }
                                              if(s>1)
                                               {
                                                fofFvect(s)=((Fnew*selectivity(j,r,y,s,x))/(Fnew*selectivity(j,r,y,s,x)+M(j,r,y,s)))*biomass_AM_overlap_age_region_all_natal(j,r,y,s)*(1-mfexp(-1*(Fnew*selectivity(j,r,y,s,x)+M(j,r,y,s))));
                                                fprimeFhigh(s)=(((Fnew+delt)*selectivity(j,r,y,s,x))/((Fnew+delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))*biomass_AM_overlap_age_region_all_natal(j,r,y,s)*(1-mfexp(-1*((Fnew+delt)*selectivity(j,r,y,s,x)+M(j,r,y,s))));
                                                fprimeFlow(s)=(((Fnew-delt)*selectivity(j,r,y,s,x))/((Fnew-delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))*biomass_AM_overlap_age_region_all_natal(j,r,y,s)*(1-mfexp(-1*((Fnew-delt)*selectivity(j,r,y,s,x)+M(j,r,y,s))));
                                               }
                                             }
                                              fofF=sum(fofFvect)-TAC(j,r,x,y);
                                              fprimeF=(sum(fprimeFhigh)-sum(fprimeFlow))/(2.0*delt);
                                              Fnew=Fnew-(fofF/fprimeF);                                           
                                          if(Fnew<0) Fnew=0.5*(Fnew+(fofF/fprimeF));
                                          if(Fnew>max_Fnew) Fnew=max_Fnew;  //At low N, Fnew would sometimes be really high and I'd get an error message.  This prevents those errors.
                                         }
                                         } 
                                       }
                                 if(natal_homing_switch==0)
                                   {
                                               if(parse_TAC==0) //use input TAC
                                                {
                                                  if(calc_TAC_from_uMSY==0)
                                                   {
                                                    TAC(j,r,x,y)=input_TAC(j,r,x);
                                                   }
                                                   if(calc_TAC_from_uMSY==1)
                                                   {
                                                    TAC(j,r,x,y)=input_u(j,r,x)*biomass_population(j,y);
                                                   }
                                                   if(calc_TAC_from_uMSY==2)
                                                   {
                                                    TAC(j,r,x,y)=input_u(j,r,x)*biomass_AM(j,r,y);
                                                   }
                                                }
                                               if(parse_TAC==1) //use observed data to parse input_TAC by region // if multiple fleets then evenly distribute across fleets
                                                {
                                                 if(parse_TAC_source==0)
                                                  {
                                                  if(calc_TAC_from_uMSY==0)
                                                   {
                                                   if(y==1)
                                                    {
                                                     TAC(j,r,x,y)=input_TAC(j,r,x)/(nregions(j)*nfleets(j)); //partition evenly by total fleets in area
                                                    }
                                                   if(y>1) //assume rec index occurs at time of spawning so never have available in current year
                                                    {
                                                     TAC(j,r,x,y)=rec_index_prop_BM(j,r,y-1)*input_TAC(j,r,x)/nfleets(j); //partition regional quota evenly by fleets in region
                                                    }
                                                   }
                                                  if(calc_TAC_from_uMSY==1)
                                                   {
                                                   if(y==1)
                                                    {
                                                     TAC(j,r,x,y)=input_u(j,r,x)*biomass_population(j,y)/(nregions(j)*nfleets(j)); //partition evenly by total fleets in area
                                                    }
                                                   if(y>1) //assume rec index occurs at time of spawning so never have available in current year
                                                    {
                                                     TAC(j,r,x,y)=rec_index_prop_BM(j,r,y-1)*input_u(j,r,x)*biomass_population(j,y)/nfleets(j); //partition regional quota evenly by fleets in region
                                                    }
                                                   }
                                                  if(calc_TAC_from_uMSY==2)
                                                   {
                                                   if(y==1)
                                                    {
                                                     TAC(j,r,x,y)=input_u(j,r,x)*biomass_AM(j,r,y)/(nregions(j)*nfleets(j)); //partition evenly by total fleets in area
                                                    }
                                                   if(y>1) //assume rec index occurs at time of spawning so never have available in current year
                                                    {
                                                     TAC(j,r,x,y)=rec_index_prop_BM(j,r,y-1)*input_u(j,r,x)*biomass_AM(j,r,y)/nfleets(j); //partition regional quota evenly by fleets in region
                                                    }
                                                   }
                                                  }
                                                 if(parse_TAC_source==1)
                                                  {
                                                  if(calc_TAC_from_uMSY==0)
                                                   {
                                                   if(y==1)
                                                    {
                                                     TAC(j,r,x,y)=input_TAC(j,r,x)/(nregions(j)*nfleets(j)); //partition evenly by total fleets in area
                                                    }
                                                   if(y>1) //assume rec index occurs at time of spawning so never have available in current year
                                                    {
                                                     TAC(j,r,x,y)=rec_index_prop_AM(j,r,y-1)*input_TAC(j,r,x)/nfleets(j); //partition regional quota evenly by fleets in region
                                                    }
                                                   }
                                                  if(calc_TAC_from_uMSY==1)
                                                   {
                                                   if(y==1)
                                                    {
                                                     TAC(j,r,x,y)=input_u(j,r,x)*biomass_population(j,y)/(nregions(j)*nfleets(j)); //partition evenly by total fleets in area
                                                    }
                                                   if(y>1) //assume rec index occurs at time of spawning so never have available in current year
                                                    {
                                                     TAC(j,r,x,y)=rec_index_prop_AM(j,r,y-1)*input_u(j,r,x)*biomass_population(j,y)/nfleets(j); //partition regional quota evenly by fleets in region
                                                    }
                                                   }
                                                  if(calc_TAC_from_uMSY==2)
                                                   {
                                                   if(y==1)
                                                    {
                                                     TAC(j,r,x,y)=input_u(j,r,x)*biomass_AM(j,r,y)/(nregions(j)*nfleets(j)); //partition evenly by total fleets in area
                                                    }
                                                   if(y>1) //assume rec index occurs at time of spawning so never have available in current year
                                                    {
                                                     TAC(j,r,x,y)=rec_index_prop_AM(j,r,y-1)*input_u(j,r,x)*biomass_AM(j,r,y)/nfleets(j); //partition regional quota evenly by fleets in region
                                                    }
                                                   }
                                                  }
                                                 if(parse_TAC_source==2)
                                                  {
                                                  if(calc_TAC_from_uMSY==0)
                                                   {
                                                   if(TAC_survey_parse_timelag_switch==1) //use timelag
                                                    {
                                                       if(y<=TAC_survey_parse_timelag) //apportion TAC equally among fleets if y<timelag
                                                        {                                                     
                                                         TAC(j,r,x,y)=input_TAC(j,r,x)/(nregions(j)*nfleets(j));
                                                        }
                                                       if(y>TAC_survey_parse_timelag)
                                                        {                                                     
                                                         TAC(j,r,x,y)=apport_region_survey_biomass(j,r,(y-TAC_survey_parse_timelag))*input_TAC(j,r,x)/nfleets(j);
                                                        }
                                                     }
                                                  if(TAC_survey_parse_timelag_switch==0) //no timelag
                                                    {
                                                     if(tsurvey(j,r)==0)
                                                      {
                                                       TAC(j,r,x,y)=apport_region_survey_biomass(j,r,y)*input_TAC(j,r,x)/nfleets(j);
                                                      }
                                                     if(tsurvey(j,r)>0)
                                                      {
                                                       if(y==1) //first year apportion TAC equally among fleets
                                                        {                                                     
                                                         TAC(j,r,x,y)=input_TAC(j,r,x)/(nregions(j)*nfleets(j));
                                                        }
                                                       if(y>1)
                                                        {                                                     
                                                         TAC(j,r,x,y)=apport_region_survey_biomass(j,r,y-1)*input_TAC(j,r,x)/nfleets(j);
                                                        }
                                                       }
                                                     }
                                                    }
                                                  if(calc_TAC_from_uMSY==1)
                                                   {
                                                   if(TAC_survey_parse_timelag_switch==1) //use timelag
                                                    {
                                                       if(y<=TAC_survey_parse_timelag)
                                                        {                                                     
                                                         TAC(j,r,x,y)=input_u(j,r,x)*biomass_population(j,y)/(nregions(j)*nfleets(j));
                                                        }
                                                       if(y>TAC_survey_parse_timelag)
                                                        {                                                     
                                                         TAC(j,r,x,y)=apport_region_survey_biomass(j,r,(y-TAC_survey_parse_timelag))*input_u(j,r,x)*biomass_population(j,y)/nfleets(j);
                                                        }
                                                     }
                                                  if(TAC_survey_parse_timelag_switch==0) //no timelag
                                                    {
                                                     if(tsurvey(j,r)==0)
                                                      {
                                                       TAC(j,r,x,y)=apport_region_survey_biomass(j,r,y)*input_u(j,r,x)*biomass_population(j,y)/nfleets(j);
                                                      }
                                                     if(tsurvey(j,r)>0)
                                                      {
                                                       if(y==1) //first year apportion TAC equally among fleets
                                                        {                                                     
                                                         TAC(j,r,x,y)=input_u(j,r,x)*biomass_population(j,y)/(nregions(j)*nfleets(j));
                                                        }
                                                       if(y>1)
                                                        {                                                     
                                                         TAC(j,r,x,y)=apport_region_survey_biomass(j,r,y-1)*input_u(j,r,x)*biomass_population(j,y)/nfleets(j);
                                                        }
                                                       }
                                                     }
                                                    }
                                                  if(calc_TAC_from_uMSY==2)
                                                   {
                                                   if(TAC_survey_parse_timelag_switch==1) //use timelag
                                                    {
                                                       if(y<=TAC_survey_parse_timelag)
                                                        {                                                     
                                                         TAC(j,r,x,y)=input_u(j,r,x)*biomass_AM(j,r,y)/(nregions(j)*nfleets(j));
                                                        }
                                                       if(y>TAC_survey_parse_timelag)
                                                        {                                                     
                                                         TAC(j,r,x,y)=apport_region_survey_biomass(j,r,(y-TAC_survey_parse_timelag))*input_u(j,r,x)*biomass_AM(j,r,y)/nfleets(j);
                                                        }
                                                     }
                                                  if(TAC_survey_parse_timelag_switch==0) //no timelag
                                                    {
                                                     if(tsurvey(j,r)==0)
                                                      {
                                                       TAC(j,r,x,y)=apport_region_survey_biomass(j,r,y)*input_u(j,r,x)*biomass_AM(j,r,y)/nfleets(j);
                                                      }
                                                     if(tsurvey(j,r)>0)
                                                      {
                                                       if(y==1) //first year apportion TAC equally among fleets
                                                        {                                                     
                                                         TAC(j,r,x,y)=input_u(j,r,x)*biomass_AM(j,r,y)/(nregions(j)*nfleets(j));
                                                        }
                                                       if(y>1)
                                                        {                                                     
                                                         TAC(j,r,x,y)=apport_region_survey_biomass(j,r,y-1)*input_u(j,r,x)*biomass_AM(j,r,y)/nfleets(j);
                                                        }
                                                       }
                                                     }
                                                    }
                                                   }
                                                 if(parse_TAC_source==3)
                                                  {
                                                  if(calc_TAC_from_uMSY==0)
                                                   {
                                                    TAC(j,r,x,y)=input_TAC(j,r,x)/(nregions(j)*nfleets(j));
                                                   }
                                                  if(calc_TAC_from_uMSY==1)
                                                   {
                                                    TAC(j,r,x,y)=input_u(j,r,x)*biomass_population(j,y)/(nregions(j)*nfleets(j));
                                                   }
                                                  if(calc_TAC_from_uMSY==2)
                                                   {
                                                    TAC(j,r,x,y)=input_u(j,r,x)*biomass_AM(j,r,y)/(nregions(j)*nfleets(j));
                                                   }
                                                  }
                                                 }
                                     if(TAC(j,r,x,y)==0) //iterationp have trouble finding F=0 when target=0; but they work great for >0 values.  This prevents those issues
                                       {
                                        Fnew=0;
                                       }
                                     if(TAC(j,r,x,y)>0) //iterationp have trouble finding F=0 when target=0; but they work great for >0 values.  This prevents those issues
                                      {
                                        Fnew=Fnew_start;
                                        for(int i=1;i<=NR_iterationp;i++)  //newton-raphson iterationp
                                         {
                                          delt=Fnew*NR_dev;  // NR_dev~0.001
                                           for(int s=1;s<=nages;s++)
                                            {
                                              if(s==1)
                                              {
                                               fofFvect(s)=weight_catch(j,r,y,s)*((Fnew*selectivity(j,r,y,s,x))/(Fnew*selectivity(j,r,y,s,x)+M(j,r,y,s)))*abundance_at_age_AM(j,r,y,s)*(1-mfexp(-1*(Fnew*selectivity(j,r,y,s,x)+M(j,r,y,s))*(1-tspawn(j))));
                                               fprimeFhigh(s)=weight_catch(j,r,y,s)*(((Fnew+delt)*selectivity(j,r,y,s,x))/((Fnew+delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))*abundance_at_age_AM(j,r,y,s)*(1-mfexp(-1*((Fnew+delt)*selectivity(j,r,y,s,x)+M(j,r,y,s))*(1-tspawn(j))));
                                               fprimeFlow(s)=weight_catch(j,r,y,s)*(((Fnew-delt)*selectivity(j,r,y,s,x))/((Fnew-delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))*abundance_at_age_AM(j,r,y,s)*(1-mfexp(-1*((Fnew-delt)*selectivity(j,r,y,s,x)+M(j,r,y,s))*(1-tspawn(j))));                                              
                                              }
                                              if(s>1)
                                              {
                                              fofFvect(s)=weight_catch(j,r,y,s)*((Fnew*selectivity(j,r,y,s,x))/(Fnew*selectivity(j,r,y,s,x)+M(j,r,y,s)))*abundance_at_age_AM(j,r,y,s)*(1-mfexp(-1*(Fnew*selectivity(j,r,y,s,x)+M(j,r,y,s))));
                                              fprimeFhigh(s)=weight_catch(j,r,y,s)*(((Fnew+delt)*selectivity(j,r,y,s,x))/((Fnew+delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))*abundance_at_age_AM(j,r,y,s)*(1-mfexp(-1*((Fnew+delt)*selectivity(j,r,y,s,x)+M(j,r,y,s))));
                                              fprimeFlow(s)=weight_catch(j,r,y,s)*(((Fnew-delt)*selectivity(j,r,y,s,x))/((Fnew-delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))*abundance_at_age_AM(j,r,y,s)*(1-mfexp(-1*((Fnew-delt)*selectivity(j,r,y,s,x)+M(j,r,y,s))));
                                              }
                                             }
                                            fofF=sum(fofFvect)-TAC(j,r,x,y);
                                            fprimeF=(sum(fprimeFhigh)-sum(fprimeFlow))/(2.0*delt);
                                            Fnew=Fnew-(fofF/fprimeF);
                                          if(Fnew<0) Fnew=0.5*(Fnew+(fofF/fprimeF));
                                          if(Fnew>max_Fnew) Fnew=max_Fnew;  //At low N, Fnew would sometimes be really high and I'd get an error message.  This prevents those errors.
                                         }
                                       } 
                                      }
                                     }

                             if(model_type_switch==2)
                                {
                                 if(natal_homing_switch>0)
                                   {
                                               if(parse_TAC==0) //use observed data to parse input_TAC by region // if multiple fleets then evenly distribute across fleets
                                                {
                                                 u(j,r,x)=input_u(j,r,x);
                                                }
                                               if(parse_TAC==1) //use observed data to parse input_TAC by region // if multiple fleets then evenly distribute across fleets
                                                {
                                                 if(parse_TAC_source==0)
                                                  {
                                                   if(y==1)
                                                    {
                                                     u(j,r,x)=input_u(j,r,x)/(nregions(j)*nfleets(j));
                                                    }
                                                   if(y>1)
                                                    {
                                                     u(j,r,x)=rec_index_prop_BM(j,r,y-1)*input_u(j,r,x)/nfleets(j);
                                                    }
                                                  }
                                                 if(parse_TAC_source==1)
                                                  {
                                                   if(y==1)
                                                    {
                                                     u(j,r,x)=input_u(j,r,x)/(nregions(j)*nfleets(j));
                                                    }
                                                   if(y>1)
                                                    {
                                                     u(j,r,x)=rec_index_prop_AM(j,r,y-1)*input_u(j,r,x)/nfleets(j);
                                                    }
                                                   }
                                                 if(parse_TAC_source==2)
                                                  {
                                                   if(TAC_survey_parse_timelag_switch==1) //use timelag
                                                    {
                                                       if(y<=TAC_survey_parse_timelag) //first year apportion TAC equally among fleets
                                                        {                                                     
                                                         u(j,r,x)=input_u(j,r,x)/(nregions(j)*nfleets(j));
                                                        }
                                                       if(y>TAC_survey_parse_timelag)
                                                        {                                                     
                                                         u(j,r,x)=apport_region_survey_biomass(j,r,(y-TAC_survey_parse_timelag))*input_u(j,r,x)/nfleets(j);
                                                        }
                                                     }
                                                  if(TAC_survey_parse_timelag_switch==0) //no timelag
                                                    {
                                                     if(tsurvey(j,r)==0)
                                                      {
                                                       u(j,r,x)=apport_region_survey_biomass(j,r,y)*input_u(j,r,x)/nfleets(j);
                                                      }
                                                     if(tsurvey(j,r)>0)
                                                      {
                                                       if(y==1) //first year apportion TAC equally among fleets
                                                        {                                                     
                                                         u(j,r,x)=input_u(j,r,x)/(nregions(j)*nfleets(j));
                                                        }
                                                       if(y>1)
                                                        {                                                     
                                                         u(j,r,x)=apport_region_survey_biomass(j,r,y-1)*input_u(j,r,x)/nfleets(j);
                                                        }
                                                       }
                                                     }
                                                    }
                                                 if(parse_TAC_source==3)
                                                  {
                                                   u(j,r,x)=input_u(j,r,x)/(nregions(j)*nfleets(j));
                                                  }
                                                 }
                                     if(u(j,r,x)==0) //iterationp have trouble finding F=0 when target=0; but they work great for >0 values.  This prevents those issues
                                       {
                                        Fnew=0;
                                       }
                                     if(u(j,r,x)>0) //iterationp have trouble finding F=0 when target=0; but they work great for >0 values.  This prevents those issues
                                      {
                                        Fnew=Fnew_start;
                                        for(int i=1;i<=NR_iterationp;i++)  //newton-raphson iterationp
                                         {
                                          delt=Fnew*NR_dev;  // NR_dev~0.001
                                           for(int s=1;s<=nages;s++)
                                             {
                                              if(s==1)
                                               {  
                                                 fofFvect(s)=(((Fnew*selectivity(j,r,y,s,x))/(Fnew*selectivity(j,r,y,s,x)+M(j,r,y,s)))*biomass_AM_overlap_age_region_all_natal(j,r,y,s)*(1-mfexp(-1*(Fnew*selectivity(j,r,y,s,x)+M(j,r,y,s))*(1-tspawn(j)))))/biomass_AM_overlap_region_all_natal(j,r,y);
                                                 fprimeFhigh(s)=((((Fnew+delt)*selectivity(j,r,y,s,x))/((Fnew+delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))*biomass_AM_overlap_age_region_all_natal(j,r,y,s)*(1-mfexp(-1*((Fnew+delt)*selectivity(j,r,y,s,x)+M(j,r,y,s))*(1-tspawn(j)))))/biomass_AM_overlap_region_all_natal(j,r,y);
                                                 fprimeFlow(s)=((((Fnew-delt)*selectivity(j,r,y,s,x))/((Fnew-delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))*biomass_AM_overlap_age_region_all_natal(j,r,y,s)*(1-mfexp(-1*((Fnew-delt)*selectivity(j,r,y,s,x)+M(j,r,y,s))*(1-tspawn(j)))))/biomass_AM_overlap_region_all_natal(j,r,y);                                              
                                               }
                                              if(s>1)
                                               {
                                                fofFvect(s)=(((Fnew*selectivity(j,r,y,s,x))/(Fnew*selectivity(j,r,y,s,x)+M(j,r,y,s)))*biomass_AM_overlap_age_region_all_natal(j,r,y,s)*(1-mfexp(-1*(Fnew*selectivity(j,r,y,s,x)+M(j,r,y,s)))))/biomass_AM_overlap_region_all_natal(j,r,y);
                                                fprimeFhigh(s)=((((Fnew+delt)*selectivity(j,r,y,s,x))/((Fnew+delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))*biomass_AM_overlap_age_region_all_natal(j,r,y,s)*(1-mfexp(-1*((Fnew+delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))))/biomass_AM_overlap_region_all_natal(j,r,y);
                                                fprimeFlow(s)=((((Fnew-delt)*selectivity(j,r,y,s,x))/((Fnew-delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))*biomass_AM_overlap_age_region_all_natal(j,r,y,s)*(1-mfexp(-1*((Fnew-delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))))/biomass_AM_overlap_region_all_natal(j,r,y);
                                               }
                                             } 
                                            fofF=sum(fofFvect)-u(j,r,x);
                                            fprimeF=(sum(fprimeFhigh)-sum(fprimeFlow))/(2.0*delt);
                                            Fnew=Fnew-(fofF/fprimeF);
                                          if(Fnew<0) Fnew=0.5*(Fnew+(fofF/fprimeF));
                                          if(Fnew>max_Fnew) Fnew=max_Fnew;  //At low N, Fnew would sometimes be really high and I'd get an error message.  This prevents those errors.
                                         }
                                         } 
                                       }
                                 if(natal_homing_switch==0)
                                   {
                                               if(parse_TAC==0) //use observed data to parse input_TAC by region // if multiple fleets then evenly distribute across fleets
                                                {
                                                 u(j,r,x)=input_u(j,r,x);
                                                }
                                               if(parse_TAC==1) //use observed data to parse input_TAC by region // if multiple fleets then evenly distribute across fleets
                                                {
                                                 if(parse_TAC_source==0)
                                                  {
                                                   if(y==1)
                                                    {
                                                     u(j,r,x)=input_u(j,r,x)/(nregions(j)*nfleets(j));
                                                    }
                                                   if(y>1)
                                                    {
                                                     u(j,r,x)=rec_index_prop_BM(j,r,y-1)*input_u(j,r,x)/nfleets(j);
                                                    }
                                                  }
                                                 if(parse_TAC_source==1)
                                                  {
                                                   if(y==1)
                                                    {
                                                     u(j,r,x)=input_u(j,r,x)/(nregions(j)*nfleets(j));
                                                    }
                                                   if(y>1)
                                                    {
                                                     u(j,r,x)=rec_index_prop_AM(j,r,y-1)*input_u(j,r,x)/nfleets(j);
                                                    }
                                                   }
                                                 if(parse_TAC_source==2)
                                                  {
                                                   if(TAC_survey_parse_timelag_switch==1) //use timelag
                                                    {
                                                       if(y<=TAC_survey_parse_timelag) //first year apportion TAC equally among fleets
                                                        {                                                     
                                                         u(j,r,x)=input_u(j,r,x)/(nregions(j)*nfleets(j));
                                                        }
                                                       if(y>TAC_survey_parse_timelag)
                                                        {                                                     
                                                         u(j,r,x)=apport_region_survey_biomass(j,r,(y-TAC_survey_parse_timelag))*input_u(j,r,x)/nfleets(j);
                                                        }
                                                     }
                                                  if(TAC_survey_parse_timelag_switch==0) //no timelag
                                                    {
                                                     if(tsurvey(j,r)==0)
                                                      {
                                                       u(j,r,x)=apport_region_survey_biomass(j,r,y)*input_u(j,r,x)/nfleets(j);
                                                      }
                                                     if(tsurvey(j,r)>0)
                                                      {
                                                       if(y==1) //first year apportion TAC equally among fleets
                                                        {                                                     
                                                         u(j,r,x)=input_u(j,r,x)/(nregions(j)*nfleets(j));
                                                        }
                                                       if(y>1)
                                                        {                                                     
                                                         u(j,r,x)=apport_region_survey_biomass(j,r,y-1)*input_u(j,r,x)/nfleets(j);
                                                        }
                                                       }
                                                     }
                                                    }
                                                 if(parse_TAC_source==3)
                                                  {
                                                   u(j,r,x)=input_u(j,r,x)/(nregions(j)*nfleets(j));
                                                  }
                                                 }
                                     if(u(j,r,x)==0) //iterationp have trouble finding F=0 when target=0; but they work great for >0 values.  This prevents those issues
                                       {
                                        Fnew=0;
                                       }
                                     if(u(j,r,x)>0) //iterationp have trouble finding F=0 when target=0; but they work great for >0 values.  This prevents those issues
                                      {
                                        Fnew=Fnew_start;
                                        for(int i=1;i<=NR_iterationp;i++)  //newton-raphson iterationp
                                         {
                                          delt=Fnew*NR_dev;  // NR_dev~0.001
                                           for(int s=1;s<=nages;s++)
                                            {
                                              if(s==1)
                                              {
                                               fofFvect(s)=(weight_catch(j,r,y,s)*((Fnew*selectivity(j,r,y,s,x))/(Fnew*selectivity(j,r,y,s,x)+M(j,r,y,s)))*abundance_at_age_AM(j,r,y,s)*(1-mfexp(-1*(Fnew*selectivity(j,r,y,s,x)+M(j,r,y,s))*(1-tspawn(j)))))/biomass_AM(j,r,y);
                                               fprimeFhigh(s)=(weight_catch(j,r,y,s)*(((Fnew+delt)*selectivity(j,r,y,s,x))/((Fnew+delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))*abundance_at_age_AM(j,r,y,s)*(1-mfexp(-1*((Fnew+delt)*selectivity(j,r,y,s,x)+M(j,r,y,s))*(1-tspawn(j)))))/biomass_AM(j,r,y);
                                               fprimeFlow(s)=(weight_catch(j,r,y,s)*(((Fnew-delt)*selectivity(j,r,y,s,x))/((Fnew-delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))*abundance_at_age_AM(j,r,y,s)*(1-mfexp(-1*((Fnew-delt)*selectivity(j,r,y,s,x)+M(j,r,y,s))*(1-tspawn(j)))))/biomass_AM(j,r,y);                                              
                                              }
                                              if(s>1)
                                              {
                                              fofFvect(s)=(weight_catch(j,r,y,s)*((Fnew*selectivity(j,r,y,s,x))/(Fnew*selectivity(j,r,y,s,x)+M(j,r,y,s)))*abundance_at_age_AM(j,r,y,s)*(1-mfexp(-1*(Fnew*selectivity(j,r,y,s,x)+M(j,r,y,s)))))/biomass_AM(j,r,y);
                                              fprimeFhigh(s)=(weight_catch(j,r,y,s)*(((Fnew+delt)*selectivity(j,r,y,s,x))/((Fnew+delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))*abundance_at_age_AM(j,r,y,s)*(1-mfexp(-1*((Fnew+delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))))/biomass_AM(j,r,y);
                                              fprimeFlow(s)=(weight_catch(j,r,y,s)*(((Fnew-delt)*selectivity(j,r,y,s,x))/((Fnew-delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))*abundance_at_age_AM(j,r,y,s)*(1-mfexp(-1*((Fnew-delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))))/biomass_AM(j,r,y);
                                              }
                                             }
                                            fofF=sum(fofFvect)-u(j,r,x);
                                            fprimeF=(sum(fprimeFhigh)-sum(fprimeFlow))/(2.0*delt);
                                            Fnew=Fnew-(fofF/fprimeF);
                                          if(Fnew<0) Fnew=0.5*(Fnew+(fofF/fprimeF));
                                          if(Fnew>max_Fnew) Fnew=max_Fnew;  //At low N, Fnew would sometimes be really high and I'd get an error message.  This prevents those errors.
                                         }
                                       } 
                                      }
                                     }
                             F_fleet(j,r,y,a,x)=Fnew*selectivity(j,r,y,a,x);                                         
                         }
                       F(j,r,y,a)=sum(F_fleet(j,r,y,a)); 
                      }                     
                     }
                    }
                   }
                  }
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
         for (int a=1;a<=nages;a++)
           {
           for (int p=1;p<=npops;p++)
            {
             for (int j=1;j<=npops;j++)
              {
               for (int r=1;r<=nregions(j);r++)
                {
                 for (int z=1;z<=nfleets(j);z++)
                  {
                abundance_spawn_overlap(p,j,r,y,a)=abundance_at_age_AM_overlap_region(p,j,y,a,r)*mfexp(-(M(j,r,y,a)+F(j,r,y,a))*tspawn(p));
                SSB_region_temp_overlap(p,j,r,y,a)=abundance_spawn_overlap(p,j,r,y,a)*wt_mat_mult_reg(p,r,y,a); //changed mat by region
                SSB_region_overlap(p,j,r,y)=sum(SSB_region_temp_overlap(p,j,r,y));

                  SSB_overlap_natal=0;
                  if(natal_homing_switch==1 && spawn_return_switch==1)
                   {
                    for(int k=1;k<=npops;k++)
                     {
                      for (int n=1;n<=nregions(k);n++)
                       {
                        if(p==k && j==k)
                         {
                          SSB_overlap_natal(k,n)=0;  // already account for all fish already in natal population in calc below
                         }   
                        if(p==j && j!=k)
                         {
                          SSB_overlap_natal(k,n)=spawn_return_prob(p)*SSB_region_overlap(p,k,n,y);
                         } 
                       }
                      } 
                      if(p==j)
                      {
                       SSB_region_overlap(p,j,r,y)=SSB_region_overlap(p,j,r,y)+(sum(SSB_overlap_natal)/nregions(p));  //reutrning SSB is split evenly across natal regionp
                       }
                   }
                   
                SSB_population_temp_overlap(p,j,y,r)=SSB_region_overlap(p,j,r,y); 
                SSB_population_overlap(p,j,y)=sum(SSB_population_temp_overlap(p,j,y));
                SSB_natal_overlap_temp(p,y,j)=SSB_population_overlap(p,j,y);
                SSB_natal_overlap(p,y)=sum(SSB_natal_overlap_temp(p,y));
                abundance_natal_temp_overlap(p,y,a,j)=abundance_at_age_AM_overlap_population(p,j,y,a);
                abundance_natal_overlap(p,y,a)=sum(abundance_natal_temp_overlap(p,y,a));
                if(a==1)
                 {
                  catch_at_age_region_overlap(p,j,r,y,a)=abundance_at_age_AM_overlap_region(p,j,y,a,r)*(1.0-mfexp(-(F(j,r,y,a)+M(j,r,y,a))*(1-tspawn(p))))*(F(j,r,y,a)/(F(j,r,y,a)+M(j,r,y,a)));
                  catch_at_age_region_fleet_overlap(p,j,r,z,y,a)=abundance_at_age_AM_overlap_region(p,j,y,a,r)*(1.0-mfexp(-(F_fleet(j,r,y,a,z)+M(j,r,y,a))*(1-tspawn(p))))*(F_fleet(j,r,y,a,z)/(F_fleet(j,r,y,a,z)+M(j,r,y,a)));              
                 }
                if(a>1)
                 {
                  catch_at_age_region_overlap(p,j,r,y,a)=abundance_at_age_AM_overlap_region(p,j,y,a,r)*(1.0-mfexp(-(F(j,r,y,a)+M(j,r,y,a))))*(F(j,r,y,a)/(F(j,r,y,a)+M(j,r,y,a))); //
                  catch_at_age_region_fleet_overlap(p,j,r,z,y,a)=abundance_at_age_AM_overlap_region(p,j,y,a,r)*(1.0-mfexp(-(F_fleet(j,r,y,a,z)+M(j,r,y,a))))*(F_fleet(j,r,y,a,z)/(F_fleet(j,r,y,a,z)+M(j,r,y,a)));              
                 }
                yield_region_fleet_temp_overlap(p,j,r,z,y,a)=weight_catch(p,r,y,a)*catch_at_age_region_fleet_overlap(p,j,r,z,y,a);
                yield_region_fleet_overlap(p,j,r,z,y)=sum(yield_region_fleet_temp_overlap(p,j,r,z,y));
                yield_region_temp_overlap(p,j,r,y,a)=weight_catch(p,r,y,a)*catch_at_age_region_overlap(p,j,r,y,a);
                yield_region_overlap(p,j,r,y)=sum(yield_region_temp_overlap(p,j,r,y));
                catch_at_age_population_temp_overlap(p,j,y,a,r)=catch_at_age_region_overlap(p,j,r,y,a);
                catch_at_age_population_overlap(p,j,y,a)=sum(catch_at_age_population_temp_overlap(p,j,y,a));
                yield_population_temp_overlap(p,j,y,a)=weight_catch(p,r,y,a)*catch_at_age_population_overlap(p,j,y,a);
                yield_population_overlap(p,j,y)=sum(yield_population_temp_overlap(p,j,y));
                catch_at_age_natal_temp_overlap(p,y,a,j)=catch_at_age_population_overlap(p,j,y,a);
                catch_at_age_natal_overlap(p,y,a)=sum(catch_at_age_natal_temp_overlap(p,y,a));
                yield_natal_temp_overlap(p,y,j)=yield_population_overlap(p,j,y);
                yield_natal_overlap(p,y)=sum(yield_natal_temp_overlap(p,y));
                harvest_rate_region_fleet_bio_overlap(p,j,r,z,y)=yield_region_fleet_overlap(p,j,r,z,y)/biomass_AM_overlap_region(p,j,r,y);
                harvest_rate_region_bio_overlap(p,j,r,y)=yield_region_overlap(p,j,r,y)/biomass_AM_overlap_region(p,j,r,y);
                harvest_rate_population_bio_overlap(p,j,y)=yield_population_overlap(p,j,y)/biomass_population_overlap(p,j,y);
                harvest_rate_natal_bio_overlap(p,y)=yield_natal_overlap(p,y)/biomass_natal_overlap(p,y);
                depletion_region_overlap(p,j,r,y)=biomass_AM_overlap_region(p,j,r,y)/biomass_AM_overlap_region(p,j,r,1);
                depletion_population_overlap(p,j,y)=biomass_population_overlap(p,j,y)/biomass_population_overlap(p,j,1);
                depletion_natal_overlap(p,y)=biomass_natal_overlap(p,y)/biomass_natal_overlap(p,1);
                Bratio_population_overlap(p,j,y)=SSB_population_overlap(p,j,y)/SSB_zero(p);
                Bratio_natal_overlap(p,y)=SSB_natal_overlap(p,y)/SSB_zero(p);

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////Y==1 Abundance Calcs//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////  CONTINUATION of NON-NATAL HOMING CALCS ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

                abundance_spawn(j,r,y,a)=abundance_at_age_AM(j,r,y,a)*mfexp(-(M(j,r,y,a)+F(j,r,y,a))*tspawn(j));
                if(a==1)
                 {
                  catch_at_age_fleet(j,r,y,a,z)=abundance_at_age_AM(j,r,y,a)*(1.0-exp(-(F_fleet(j,r,y,a,z)+M(j,r,y,a))*(1-tspawn(j))))*(F_fleet(j,r,y,a,z))/(F(j,r,y,a)+M(j,r,y,a));
                 }
                if(a>1)
                 {
                  catch_at_age_fleet(j,r,y,a,z)=abundance_at_age_AM(j,r,y,a)*(1.0-exp(-(F_fleet(j,r,y,a,z)+M(j,r,y,a))))*(F_fleet(j,r,y,a,z))/(F(j,r,y,a)+M(j,r,y,a));
                 }
                yield_fleet_temp(j,r,y,z,a)=weight_catch(j,r,y,a)*catch_at_age_fleet(j,r,y,a,z);
                yield_fleet(j,r,y,z)=sum(yield_fleet_temp(j,r,y,z));
                catch_at_age_region(j,r,y,a)=sum(catch_at_age_fleet(j,r,y,a));
                yield_region_temp(j,r,y,a)=weight_catch(j,r,y,a)*catch_at_age_region(j,r,y,a);
                yield_region(j,r,y)=sum(yield_region_temp(j,r,y));
                catch_at_age_population_temp(j,y,a,r)=catch_at_age_region(j,r,y,a);
                catch_at_age_population(j,y,a)=sum(catch_at_age_population_temp(j,y,a));
                yield_population_temp(j,y,a)=weight_catch(j,r,y,a)*catch_at_age_population(j,y,a);
                yield_population(j,y)=sum(yield_population_temp(j,y));
                catch_at_age_total_temp(y,a,j)=catch_at_age_population(j,y,a);
                catch_at_age_total(y,a)=sum(catch_at_age_total_temp(y,a));
                yield_total_temp(y,j)=yield_population(j,y);
                yield_total(y)=sum(yield_total_temp(y));
                harvest_rate_region_num(j,r,y,a)=catch_at_age_region(j,r,y,a)/abundance_at_age_AM(j,r,y,a);
                harvest_rate_population_num(j,y,a)=catch_at_age_population(j,y,a)/abundance_population(j,y,a);
                harvest_rate_total_num(y,a)=catch_at_age_total(y,a)/abundance_total(y,a);
                harvest_rate_region_bio(j,r,y)=yield_region(j,r,y)/biomass_AM(j,r,y);
                harvest_rate_population_bio(j,y)=yield_population(j,y)/biomass_population(j,y);
                harvest_rate_total_bio(y)=yield_total(y)/biomass_total(y);
                depletion_region(j,r,y)=biomass_AM(j,r,y)/biomass_AM(j,r,1);
                depletion_population(j,y)=biomass_population(j,y)/biomass_population(j,1);
                depletion_total(y)=biomass_total(y)/biomass_total(1);

              if(natal_homing_switch>0)
               {
               if(p==j)
               {
                SSB_region(j,r,y)=SSB_region_overlap(p,j,r,y);  //if natal homing only account for SSB that is in its natal populations area, don't sum across natal populations
               }
              }
              if(natal_homing_switch==0)
              {
                SSB_region_temp(j,r,y,a)=abundance_spawn(j,r,y,a)*wt_mat_mult_reg(j,r,y,a); // changed mat by region
                SSB_region(j,r,y)=sum(SSB_region_temp(j,r,y));
              }
                SSB_population_temp(j,y,r)=SSB_region(j,r,y); 
                SSB_population(j,y)=sum(SSB_population_temp(j,y)); 
                SSB_total_temp(y,j)=SSB_population(j,y);
                SSB_total(y)=sum(SSB_total_temp(y));
                Bratio_population(j,y)=SSB_population(j,y)/SSB_zero(j);
                Bratio_total(y)=SSB_total(y)/sum(SSB_zero);

                //YIELD observation error
                OBS_yield_region_fleet_overlap(p,j,r,y,z)=yield_region_fleet_overlap(p,j,r,z,y)*mfexp(yield_RN_overlap(p,j,r,y,z)*sigma_catch_overlap(p,j,r,z)-.5*square(sigma_catch_overlap(p,j,r,z)));
                OBS_yield_fleet_temp(j,r,y,z,p)=OBS_yield_region_fleet_overlap(p,j,r,y,z);
               if(natal_homing_switch==0)
                {
                 OBS_yield_fleet(j,r,y,z)=yield_fleet(j,r,y,z)*mfexp(yield_RN(j,r,y,z)*sigma_catch(j,r,z)-.5*square(sigma_catch(j,r,z)));
                }
               if(natal_homing_switch==1)
                {
                 OBS_yield_fleet(j,r,y,z)=sum(OBS_yield_fleet_temp(j,r,y,z));  
                }
                OBS_yield_region_overlap(p,j,y,r)=sum(OBS_yield_region_fleet_overlap(p,j,r,y));
                OBS_yield_population_overlap(p,y,j)=sum(OBS_yield_region_overlap(p,j,y));
                OBS_yield_natal_overlap(y,p)=sum(OBS_yield_population_overlap(p,y));
                OBS_yield_total_overlap(y)=sum(OBS_yield_natal_overlap(y));
                OBS_yield_region(j,y,r)=sum(OBS_yield_fleet(j,r,y));
                OBS_yield_population(y,j)=sum(OBS_yield_region(j,y));
                OBS_yield_total(y)=sum(OBS_yield_population(y));
             //apportion variables
                apport_yield_region(j,r,y)=OBS_yield_region(j,y,r)/OBS_yield_population(y,j);

          } //end fleets loop
             for (int z=1;z<=nfleets_survey(j);z++)    /// survey index  1. Currently set up for more than 1 survey fleet
              {
               if(tsurvey(j,r)>0) //if survey at beggining of year, do calcs without temporal adjustment for mortality
                {
                  true_survey_fleet_overlap_age(p,j,r,y,z,a)=survey_selectivity(j,r,y,a,z)*abundance_at_age_AM_overlap_region(p,j,y,a,r)*mfexp(-(M(j,r,y,a)+F(j,r,y,a))*tsurvey(j,r))*q_survey(j,r,z);
                  true_survey_fleet_overlap_age_bio(p,j,r,y,z,a)=true_survey_fleet_overlap_age(p,j,r,y,z,a)*weight_population(p,r,y,a);
                  true_survey_fleet_bio_overlap(p,j,r,y,z)=sum(true_survey_fleet_overlap_age_bio(p,j,r,y,z));  
                  true_survey_fleet_bio_overlap_temp(j,r,y,z,p)=true_survey_fleet_bio_overlap(p,j,r,y,z);
                  OBS_survey_fleet_bio_overlap(p,j,r,y,z)=true_survey_fleet_bio_overlap(p,j,r,y,z)*mfexp(survey_RN_overlap(p,j,r,y,z)*sigma_survey_overlap(p,j,r,z)-.5*square(sigma_survey_overlap(p,j,r,z)));
                  OBS_survey_fleet_bio_temp(j,r,y,z,p)=OBS_survey_fleet_bio_overlap(p,j,r,y,z);

                if(natal_homing_switch==0)
                 {
                  true_survey_fleet_age(j,r,y,z,a)=survey_selectivity(j,r,y,a,z)*abundance_at_age_AM(j,r,y,a)*mfexp(-(M(j,r,y,a)+F(j,r,y,a))*tsurvey(j,r))*q_survey(j,r,z);
                  true_survey_fleet_age_bio(j,r,y,z,a)=true_survey_fleet_age(j,r,y,z,a)*weight_population(j,r,y,a);                  
                  true_survey_fleet_bio(j,r,y,z)=sum(true_survey_fleet_age_bio(j,r,y,z));
                  OBS_survey_fleet_bio(j,r,y,z)=true_survey_fleet_bio(j,r,y,z)*mfexp(survey_RN(j,r,y,z)*sigma_survey(j,r,z)-.5*square(sigma_survey(j,r,z)));
                 }
                if(natal_homing_switch==1)
                 {
                  true_survey_fleet_bio(j,r,y,z)=sum(true_survey_fleet_bio_overlap_temp(j,r,y,z));
                  OBS_survey_fleet_bio(j,r,y,z)=sum(OBS_survey_fleet_bio_temp(j,r,y,z));  
                 }
             
                  true_survey_region_bio_overlap(p,j,y,r)=sum(true_survey_fleet_bio_overlap(p,j,r,y));               
                  true_survey_population_bio_overlap(p,y,j)=sum(true_survey_region_bio_overlap(p,j,y));               
                  true_survey_natal_bio_overlap(y,p)=sum(true_survey_population_bio_overlap(p,y));               
                  true_survey_total_bio_overlap(y)=sum(true_survey_natal_bio_overlap(y));
                  OBS_survey_region_bio_overlap(p,j,y,r)=sum(OBS_survey_fleet_bio_overlap(p,j,r,y));
                  OBS_survey_population_bio_overlap(p,y,j)=sum(OBS_survey_region_bio_overlap(p,j,y));
                  OBS_survey_natal_bio_overlap(y,p)=sum(OBS_survey_population_bio_overlap(p,y));
                  OBS_survey_total_bio_overlap(y)=sum(OBS_survey_natal_bio_overlap(y));
                  
                  true_survey_region_bio(j,y,r)=sum(true_survey_fleet_bio(j,r,y));
                  true_survey_population_bio(y,j)=sum(true_survey_region_bio(j,y));
                  true_survey_total_bio(y)=sum(true_survey_population_bio(y));
                  OBS_survey_region_bio(j,y,r)=sum(OBS_survey_fleet_bio(j,r,y));
                  OBS_survey_population_bio(y,j)=sum(OBS_survey_region_bio(j,y));
                  OBS_survey_total_bio(y)=sum(OBS_survey_population_bio(y));

                  apport_region_survey_biomass(j,r,y)=OBS_survey_region_bio(j,y,r)/OBS_survey_population_bio(y,j);
                  
                } //tsurvey>0
               }  //end survey_fleets 
             }
            }
           }
          }//end age loop          
        } //end yr 1
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////Recruitment Calcs///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

////need to fix and use SSB and R_ave for BH calcs.

    if(y>1)
     {
        for (int a=1;a<=nages;a++)
          {
           for (int p=1;p<=npops;p++)
            {
             for (int j=1;j<=npops;j++)
              {
               for (int r=1;r<=nregions(j);r++)
                {
                 for (int z=1;z<=nfleets(j);z++)
                  {
                   if(a==1)
                   {
                 if(natal_homing_switch>0)
                 {
                 if(p==j)
                 {
                 if(Rec_type==1) //average recruitment
                  {
                   if(apportionment_type==1 || apportionment_type==2 ||apportionment_type==3||apportionment_type==4||apportionment_type==(-1)) //use prespecified Rec_Prop to apportion recruitment among regions within a population
                    {
                     recruits_BM(j,r,y)=R_ave(j)*rec_devs(j,y)*Rec_Prop(j,r,y);
                    }
                   if(apportionment_type==0)  //use relative SSB to apportion recruitment among regionp within a population
                    {
                     recruits_BM(j,r,y)=R_ave(j)*rec_devs(j,y)*(SSB_region_overlap(p,j,r,y-1)/sum(SSB_region_overlap(p,j,y-1))); //assume with natal homing that fish aren't from a particular region so when apportion them use relative SSB in each region (but don't account for SSB that moves back to the region to spawn ie fish that move back add to population SSB but not region SSB)
                    }
                  }

                 if(Rec_type==2) //BH recruitment
                  {
                   if(apportionment_type==1 || apportionment_type==2 ||apportionment_type==3||apportionment_type==4||apportionment_type==(-1))  //use prespecified Rec_Prop to apportion recruitment among regions within a population
                    {
                    recruits_BM(j,r,y)=((SSB_population_overlap(p,j,y-1))/(alpha(j)+beta(j)*SSB_population_overlap(p,j,y-1)))*rec_devs(j,y)*Rec_Prop(j,r,y);
                    }
                   if(apportionment_type==0) //use relative SSB to apportion recruitment among regions within a population
                    {
                     recruits_BM(j,r,y)=((SSB_population_overlap(p,j,y-1))/(alpha(j)+beta(j)*SSB_population_overlap(p,j,y-1)))*rec_devs(j,y)*(SSB_region_overlap(p,j,r,y-1)/sum(SSB_region_overlap(p,j,y-1)));
                    }
                  }
                  
                if(Rec_type==3) //environmental recruitment
                  {
                   if(apportionment_type==1 || apportionment_type==2 ||apportionment_type==3||apportionment_type==4||apportionment_type==(-1)) //use prespecified Rec_Prop to apportion recruitment among regionp within a population
                    {
                     recruits_BM(j,r,y)=env_rec(y)*rec_devs(j,y)*Rec_Prop(j,r,y);
                    }
                   if(apportionment_type==0)  //use relative SSB to apportion recruitment among regions within a population
                    {
                     recruits_BM(j,r,y)=env_rec(y)*rec_devs(j,y)*(SSB_region_overlap(p,j,r,y-1)/sum(SSB_region_overlap(p,j,y-1))); //assume with natal homing that fish aren't from a particular region so when apportion them use relative SSB in each region (but don't account for SSB that moves back to the region to spawn ie fish that move back add to population SSB but not region SSB)
                    }
                  }
                 }
                 }

             if(natal_homing_switch==0)
              {
                if(Rec_type==1) //average recruitment
                  {
                  if(apportionment_type==1 || apportionment_type==2 ||apportionment_type==3||apportionment_type==4||apportionment_type==(-1)) //use prespecified Rec_Prop to apportion recruitment among regionp within a population
                    {
                    recruits_BM(j,r,y)=R_ave(j)*rec_devs(j,y)*Rec_Prop(j,r,y);
                    }
                    if(apportionment_type==0)  //use relative SSB to apportion recruitment among regionp within a population
                    {
                    recruits_BM(j,r,y)=R_ave(j)*rec_devs(j,y)*(SSB_region(j,r,y-1)/SSB_population(j,y-1));
                    }
                  }
                 if(Rec_type==2) //BH recruitment
                  {
                   if(apportionment_type==1 || apportionment_type==2 ||apportionment_type==3||apportionment_type==4||apportionment_type==(-1))  //use prespecified Rec_Prop to apportion recruitment among regionp within a population
                    {
                     recruits_BM(j,r,y)=((SSB_population(j,y-1))/(alpha(j)+beta(j)*SSB_population(j,y-1)))*rec_devs(j,y)*Rec_Prop(j,r,y);
                    }
                   if(apportionment_type==0) //use relative SSB to apportion recruitment among regionp within a population
                    {
                     recruits_BM(j,r,y)=((SSB_population(j,y-1))/(alpha(j)+beta(j)*SSB_population(j,y-1)))*rec_devs(j,y)*(SSB_region(j,r,y-1)/SSB_population(j,y-1));
                    }
                   }

                if(Rec_type==3) //average recruitment
                  {
                  if(apportionment_type==1 || apportionment_type==2 ||apportionment_type==3||apportionment_type==4||apportionment_type==(-1)) //use prespecified Rec_Prop to apportion recruitment among regionp within a population
                    {
                     recruits_BM(j,r,y)=env_rec(y)* rec_devs(j,y)*Rec_Prop(j,r,y);
                    }
                   if(apportionment_type==0)  //use relative SSB to apportion recruitment among regionp within a population
                   {
                    recruits_BM(j,r,y)=env_rec(y)* R_ave(j)*rec_devs(j,y)*(SSB_region(j,r,y-1)/SSB_population(j,y-1));
                   }
                 }
                 }
               rec_index_BM(j,r,y)=recruits_BM(j,r,y)*mfexp(rec_index_RN(j,r,y)*rec_index_sigma(j,r)-0.5*square(rec_index_sigma(j,r)));
               rec_index_BM_temp(j,y,r)=rec_index_BM(j,r,y);
               rec_index_prop_BM(j,r,y)=rec_index_BM(j,r,y)/sum(rec_index_BM_temp(j,y));

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////a==1 overlap calcs///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

                 if(p==j)
                 {
                   abundance_at_age_BM_overlap_region(p,j,y,a,r)=recruits_BM(j,r,y);
                 }
                 if(p!=j)
                 {
                   abundance_at_age_BM_overlap_region(p,j,y,a,r)=0;
                 }
                abundance_at_age_BM_overlap_population(p,j,y,a)=sum(abundance_at_age_BM_overlap_region(p,j,y,a));

                biomass_BM_age_overlap(p,j,r,y,a)=weight_population(p,r,y,a)*abundance_at_age_BM_overlap_region(p,j,y,a,r);
                biomass_BM_overlap_region(p,j,r,y)=sum(biomass_BM_age_overlap(p,j,r,y));
                
//////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////// metapop calcs /////////////////////////////////////////////////////////////////////////

                 abundance_at_age_BM(j,r,y,a)=recruits_BM(j,r,y);

/////////////////////////////////////////////////////////////////////////////////////////////////////////////

                  if(natal_homing_switch==0)
                   {
                    biomass_BM_age(j,r,y,a)=weight_population(j,r,y,a)*abundance_at_age_BM(j,r,y,a);
                    biomass_BM(j,r,y)=sum(biomass_BM_age(j,r,y));
                   }
                  if(natal_homing_switch>0) //if natal homing put abundance summed across natal population by region into abundance at age AM
                   {
                  if(natal_homing_switch>0) //if natal homing put abundance summed across natal population by region into abundance at age AM
                   {
                    biomass_BM_overlap_temp(j,r,y,a,p)=biomass_BM_age_overlap(p,j,r,y,a);
                    biomass_BM_age(j,r,y,a)=sum(biomass_BM_overlap_temp(j,r,y,a));
                    biomass_BM(j,r,y)=sum(biomass_BM_age(j,r,y));
                   }
                   }
              }
             }
            }
           }
          } //close loops so have full biomass vectors filled in at start of DD movement calcs
        if(a==1)
         {
           for (int p=1;p<=npops;p++)
            {
             for (int j=1;j<=npops;j++)
              {
               for (int r=1;r<=nregions(j);r++)
                {
                 for (int z=1;z<=nfleets(j);z++)
                  {
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////Density-Dependent Movement Calcs///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
           /// rel_bio gives ratio of biomass in each area weighted by ratio to Bstar, use 1-ratio of bio
            /// because want to weight T and make more fish move to area with lower bio compared to Bstar
            /// idea is that if B/Bstar<1 then not densely populated and more fish would move there
            
                    if(move_switch==8)
                     {
                      Fract_Move_DD(j,r,y,a)=((1-input_residency(j,r,a))/(1+A(j,r)*mfexp(c(j,r)*biomass_BM_age(j,r,y,a))));
       
                      biomass_BM_temp=0;
                      biomass_BM_temp2=0;
                       for (int s=1;s<=npops;s++)
                        {
                         for (int n=1;n<=nregions(s);n++)
                          {       
                           biomass_BM_temp(s,n)=biomass_BM_age(s,n,y,a)/Bstar(s,n);
                          }
                        }
                       biomass_BM_temp2=sum(biomass_BM_temp)-(biomass_BM_age(j,r,y,a)/Bstar(j,r)); //do not include population/region moving from in summation
                        for (int s=1;s<=npops;s++)
                         {
                          for (int n=1;n<=nregions(s);n++)
                           {
                            if(j==s && r==n) //do not include current pop/region in calcs (residency is already defined)
                             {
                              rel_bio(j,r,y,a,s,n)=0;  //rel bio defined for movement out of pop j region r as suitability of destination population s, region n
                             }
                            if(j!=s || r!=n) 
                             {
                              rel_bio(j,r,y,a,s,n)=1-((biomass_BM_temp(s,n))/(biomass_BM_temp2));
                             }
                            if(sum(nregions)==2)
                             {
                              rel_bio(j,r,y,a,s,n)=1;
                             }
                            }
                           }
                       for (int s=1;s<=npops;s++)
                        {
                         for (int n=1;n<=nregions(s);n++)
                          {
                           if(j==s && r==n) 
                            {
                             T(j,r,y,a,s,n)=1-Fract_Move_DD(j,r,y,a);
                            }
                           if(j!=s || r!=n) 
                            {
                             T(j,r,y,a,s,n)=rel_bio(j,r,y,a,s,n)*Fract_Move_DD(j,r,y,a);
                            }
                          }
                        }
                    }
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

                abundance_move_overlap_temp=0;
               
                for (int k=1;k<=npops;k++)
                 {
                  for (int n=1;n<=nregions(k);n++)
                   {

  ///////////NEED TO CHECK WHY USING FULL RECRUITMENT FUNCTIOnp TO CALCULATE MOVEMENT OF AGE-1 FISH HERE, MIGHT BE ABLE TO CONDEnpE CODE AND USE RECRUITS_BM OR ABUNDANCE_BM


                 if(natal_homing_switch>0)
                 {
                 if(p==k)
                 {
                 if(Rec_type==1) //average recruitment
                  {
                   if(apportionment_type==1 || apportionment_type==2 ||apportionment_type==3||apportionment_type==4||apportionment_type==(-1)) //use prespecified Rec_Prop to apportion recruitment among regionp within a population
                    {
                      abundance_move_overlap_temp(k,n)=R_ave(k)*rec_devs(k,y)*Rec_Prop(k,n,y)*T(p,n,y,a,j,r);
                    }
                   if(apportionment_type==0)  //use relative SSB to apportion recruitment among regionp within a population
                    {
                      abundance_move_overlap_temp(k,n)=R_ave(k)*rec_devs(k,y)*(SSB_region_overlap(p,k,n,y-1)/sum(SSB_region_overlap(p,k,y-1)))*T(p,n,y,a,j,r); //assume with natal homing that fish aren't from a particular region so when apportion them use relative SSB in each region (but don't account for SSB that moves back to the region to spawn ie fish that move back add to population SSB but not region SSB)
                    }
                  }

                 if(Rec_type==2) //BH recruitment
                  {
                   if(apportionment_type==1 || apportionment_type==2 ||apportionment_type==3||apportionment_type==4||apportionment_type==(-1))  //use prespecified Rec_Prop to apportion recruitment among regionp within a population
                    {
                      abundance_move_overlap_temp(k,n)=((SSB_population_overlap(p,k,y-1))/(alpha(k)+beta(k)*SSB_population_overlap(p,k,y-1)))*rec_devs(k,y)*Rec_Prop(k,n,y)*T(p,n,y,a,j,r);
                    }
                   if(apportionment_type==0) //use relative SSB to apportion recruitment among regionp within a population
                    {
                      abundance_move_overlap_temp(k,n)=((SSB_population_overlap(p,k,y-1))/(alpha(k)+beta(k)*SSB_population_overlap(p,k,y-1)))*rec_devs(k,y)*(SSB_region_overlap(p,k,n,y-1)/sum(SSB_region_overlap(p,k,y-1)))*T(p,n,y,a,j,r);
                    }
                  }

                if(Rec_type==3) //average recruitment
                  {
                   if(apportionment_type==1 || apportionment_type==2 ||apportionment_type==3||apportionment_type==4||apportionment_type==(-1)) //use prespecified Rec_Prop to apportion recruitment among regionp within a population
                    {
                      abundance_move_overlap_temp(k,n)=env_rec(y)*rec_devs(k,y)*Rec_Prop(k,n,y)*T(p,n,y,a,j,r);
                    }
                   if(apportionment_type==0)  //use relative SSB to apportion recruitment among regionp within a population
                    {
                      abundance_move_overlap_temp(k,n)=env_rec(y)*rec_devs(k,y)*(SSB_region_overlap(p,k,n,y-1)/sum(SSB_region_overlap(p,k,y-1)))*T(p,n,y,a,j,r); //assume with natal homing that fish aren't from a particular region so when apportion them use relative SSB in each region (but don't account for SSB that moves back to the region to spawn ie fish that move back add to population SSB but not region SSB)
                    }
                  }
                 }
                 }
                 
             if(natal_homing_switch==0)
              {
                 if(Rec_type==1) //average recruitment
                  {
                   if(apportionment_type==1 || apportionment_type==2 ||apportionment_type==3||apportionment_type==4||apportionment_type==(-1)) //use prespecified Rec_Prop to apportion recruitment among regionp within a population
                    {
                    abundance_move_overlap_temp(k,n)=R_ave(k)*rec_devs(k,y)*Rec_Prop(k,n,y)*T(k,n,y,a,j,r);
                    }
                   if(apportionment_type==0)  //use relative SSB to apportion recruitment among regionp within a population
                    {
                    abundance_move_overlap_temp(k,n)=R_ave(k)*rec_devs(k,y)*(SSB_region(k,n,y-1)/SSB_population(k,y-1))*T(k,n,y,a,j,r);
                    }
                    }
                 if(Rec_type==2) //BH recruitment
                  {
                 if(apportionment_type==1 || apportionment_type==2 ||apportionment_type==3||apportionment_type==4||apportionment_type==(-1))  //use prespecified Rec_Prop to apportion recruitment among regionp within a population
                    {
                    abundance_move_overlap_temp(k,n)=((SSB_population(k,y-1))/(alpha(k)+beta(k)*SSB_population(k,y-1)))*rec_devs(k,y)*Rec_Prop(k,n,y)*T(k,n,y,a,j,r);
                    }
                   if(apportionment_type==0) //use relative SSB to apportion recruitment among regionp within a population
                    {
                     abundance_move_overlap_temp(k,n)=((SSB_population(k,y-1))/(alpha(k)+beta(k)*SSB_population(k,y-1)))*rec_devs(k,y)*(SSB_region(k,n,y-1)/SSB_population(k,y-1))*T(k,n,y,a,j,r);
                    }
                  }

                if(Rec_type==3) //environmental recruitment
                  {
                   if(apportionment_type==1 || apportionment_type==2 ||apportionment_type==3||apportionment_type==4||apportionment_type==(-1)) //use prespecified Rec_Prop to apportion recruitment among regionp within a population
                    {
                     abundance_move_overlap_temp(k,n)=env_rec(y)*rec_devs(k,y)*Rec_Prop(k,n,y)*T(k,n,y,a,j,r);
                    }
                   if(apportionment_type==0)  //use relative SSB to apportion recruitment among regionp within a population
                    {
                     abundance_move_overlap_temp(k,n)=env_rec(y)*rec_devs(k,y)*(SSB_region(k,n,y-1)/SSB_population(k,y-1))*T(k,n,y,a,j,r);
                    }
                  }

                }
                   }
                  }

                abundance_at_age_AM_overlap_region(p,j,y,a,r)=sum(abundance_move_overlap_temp);
                abundance_AM_overlap_region_all_natal_temp(j,r,y,a,p)=abundance_at_age_AM_overlap_region(p,j,y,a,r);
                biomass_AM_overlap_region_all_natal_temp(j,r,y,a,p)=abundance_at_age_AM_overlap_region(p,j,y,a,r)*weight_population(p,r,y,a);
                abundance_AM_overlap_region_all_natal(j,r,y,a)=sum(abundance_AM_overlap_region_all_natal_temp(j,r,y,a));
                biomass_AM_overlap_age_region_all_natal(j,r,y,a)=sum(biomass_AM_overlap_region_all_natal_temp(j,r,y,a));
                biomass_AM_overlap_region_all_natal(j,r,y)=sum(biomass_AM_overlap_age_region_all_natal(j,r,y));
                abundance_at_age_AM_overlap_population(p,j,y,a)=sum(abundance_at_age_AM_overlap_region(p,j,y,a));
                biomass_AM_age_overlap(p,j,r,y,a)=weight_population(p,r,y,a)*abundance_at_age_AM_overlap_region(p,j,y,a,r);
                biomass_AM_overlap_region(p,j,r,y)=sum(biomass_AM_age_overlap(p,j,r,y));
                biomass_population_temp_overlap(p,j,y,r)=biomass_AM_overlap_region(p,j,r,y);
                biomass_population_overlap(p,j,y)=sum(biomass_population_temp_overlap(p,j,y));
                biomass_natal_temp_overlap(p,y,j)=biomass_population_overlap(p,j,y);
                biomass_natal_overlap(p,y)=sum(biomass_natal_temp_overlap(p,y));
              
  ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  /////////////////////////////////y>1, A==1 METAPOP TYPE CALCS (MOVEMENT)//////////////////////////////////////////////////////////////////////////////////
  ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  

                    abundance_move_temp=0;
                    bio_move_temp=0;

        for (int k=1;k<=npops;k++)
           {
            for (int n=1;n<=nregions(k);n++)
             {
             if(natal_homing_switch==0)
              {
                 if(Rec_type==1) //average recruitment
                  {
                   if(apportionment_type==1 || apportionment_type==2 ||apportionment_type==3||apportionment_type==4||apportionment_type==(-1)) //use prespecified Rec_Prop to apportion recruitment among regionp within a population
                    {
                     abundance_move_temp(k,n)=R_ave(k)*rec_devs(k,y)*Rec_Prop(k,n,y)*T(k,n,y,a,j,r);
                     }
                   if(apportionment_type==0)  //use relative SSB to apportion recruitment among regionp within a population
                    {
                    abundance_move_temp(k,n)=R_ave(k)*rec_devs(k,y)*(SSB_region(k,n,y-1)/SSB_population(k,y-1))*T(k,n,y,a,j,r);
                    }
                  }
                 if(Rec_type==2) //BH recruitment
                  {
                   if(apportionment_type==1 || apportionment_type==2 ||apportionment_type==3||apportionment_type==4||apportionment_type==(-1))  //use prespecified Rec_Prop to apportion recruitment among regionp within a population
                    {
                    abundance_move_temp(k,n)=((SSB_population(k,y-1))/(alpha(k)+beta(k)*SSB_population(k,y-1)))*rec_devs(k,y)*Rec_Prop(k,n,y)*T(k,n,y,a,j,r);
                    }
                   if(apportionment_type==0) //use relative SSB to apportion recruitment among regionp within a population
                    {
                     abundance_move_temp(k,n)=((SSB_population(k,y-1))/(alpha(k)+beta(k)*SSB_population(k,y-1)))*rec_devs(k,y)*(SSB_region(k,n,y-1)/SSB_population(k,y-1))*T(k,n,y,a,j,r);
                    }
                  }
                if(Rec_type==3) //env recruitment
                  {
                  if(apportionment_type==1 || apportionment_type==2 ||apportionment_type==3||apportionment_type==4||apportionment_type==(-1)) //use prespecified Rec_Prop to apportion recruitment among regionp within a population
                    {
                     abundance_move_temp(k,n)=env_rec(y)*rec_devs(k,y)*Rec_Prop(k,n,y)*T(k,n,y,a,j,r);
                    }
                   if(apportionment_type==0)  //use relative SSB to apportion recruitment among regionp within a population
                    {
                     abundance_move_temp(k,n)=env_rec(y)*rec_devs(k,y)*(SSB_region(k,n,y-1)/SSB_population(k,y-1))*T(k,n,y,a,j,r);
                    }
                  }
                }
                     bio_move_temp(k,n)=abundance_move_temp(k,n)*weight_population(k,n,y,a);
              }
             }
                  
                  if(natal_homing_switch>0)
                   {                  
                    abundance_at_age_AM(j,r,y,a)=abundance_AM_overlap_region_all_natal(j,r,y,a);
                    biomass_AM(j,r,y)=biomass_AM_overlap_region_all_natal(j,r,y);                   
                   }
                  if(natal_homing_switch==0)
                   {
                    abundance_at_age_AM(j,r,y,a)=sum(abundance_move_temp);
                    biomass_AM_age(j,r,y,a)=weight_population(j,r,y,a)*abundance_at_age_AM(j,r,y,a);
                    biomass_AM(j,r,y)=sum(biomass_AM_age(j,r,y));
                   }

               recruits_AM(j,r,y)=abundance_at_age_AM(j,r,y,a);
               rec_index_AM(j,r,y)=recruits_AM(j,r,y)*mfexp(rec_index_RN(j,r,y)*rec_index_sigma(j,r)-0.5*square(rec_index_sigma(j,r)));
               rec_index_AM_temp(j,y,r)=rec_index_AM(j,r,y);
               rec_index_prop_AM(j,r,y)=rec_index_AM(j,r,y)/sum(rec_index_AM_temp(j,y));

                biomass_population_temp(j,y,r)=biomass_AM(j,r,y);
                biomass_population(j,y)=sum(biomass_population_temp(j,y));
                biomass_total_temp(y,j)=biomass_population(j,y);
                biomass_total(y)=sum(biomass_total_temp(y));

               abundance_in(j,r,y,a)=sum(abundance_move_temp)-abundance_move_temp(j,r);
               abundance_res(j,r,y,a)=abundance_move_temp(j,r);
               abundance_leave(j,r,y,a)=abundance_at_age_BM(j,r,y,a)-abundance_res(j,r,y,a);
               bio_in(j,r,y,a)=sum(bio_move_temp)-bio_move_temp(j,r);
               bio_res(j,r,y,a)=bio_move_temp(j,r);
               bio_leave(j,r,y,a)=abundance_at_age_BM(j,r,y,a)*weight_population(j,r,y,a)-bio_res(j,r,y,a);
           }
          }
         }
        }
       } //end a==1 if statement

 /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
       if(a==2) //account for partial year mortality during spawning year
        {
           for (int p=1;p<=npops;p++)
            {
             for (int j=1;j<=npops;j++)
              {
               for (int r=1;r<=nregions(j);r++)
                {
                 for (int z=1;z<=nfleets(j);z++)
                  {
                  abundance_at_age_BM_overlap_region(p,j,y,a,r)=abundance_at_age_AM_overlap_region(p,j,y-1,a-1,r)*mfexp(-(M(j,r,y-1,a-1)+F(j,r,y-1,a-1))*(1-tspawn(p)));
                  abundance_at_age_BM_overlap_population(p,j,y,a)=sum(abundance_at_age_BM_overlap_region(p,j,y,a));
                  biomass_BM_age_overlap(p,j,r,y,a)=weight_population(p,r,y,a)*abundance_at_age_BM_overlap_region(p,j,y,a,r);
                  biomass_BM_overlap_region(p,j,r,y)=sum(biomass_BM_age_overlap(p,j,r,y));

/////////////////////////metapop/////////////////////////////////////////////////////////
            abundance_at_age_BM(j,r,y,a)=abundance_at_age_AM(j,r,y-1,a-1)*mfexp(-(M(j,r,y-1,a-1)+F(j,r,y-1,a-1))*(1-tspawn(j))); //account for time of spawning (i.e., if born midway only experience a half year of mortality from age-1 to age-2)
/////////////////////////////////////////////////////////////////////////////////////////

                  if(natal_homing_switch==0)
                   {
                    biomass_BM_age(j,r,y,a)=weight_population(j,r,y,a)*abundance_at_age_BM(j,r,y,a);
                    biomass_BM(j,r,y)=sum(biomass_BM_age(j,r,y));
                   }
                  if(natal_homing_switch>0) //if natal homing put abundance summed across natal population by region into abundance at age AM
                   {
                    biomass_BM_overlap_temp(j,r,y,a,p)=biomass_BM_age_overlap(p,j,r,y,a);
                    biomass_BM_age(j,r,y,a)=sum(biomass_BM_overlap_temp(j,r,y,a));
                    biomass_BM(j,r,y)=sum(biomass_BM_age(j,r,y));
                   }
              }
             }
            }
           }
          } //close loops so have full biomass vectors filled in at start of DD movement calcs
         if(a==2)
          { 
           for (int p=1;p<=npops;p++)
            {
             for (int j=1;j<=npops;j++)
              {
               for (int r=1;r<=nregions(j);r++)
                {
                 for (int z=1;z<=nfleets(j);z++)
                  {
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////Density-Dependent Movement Calcs///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
           /// rel_bio gives ratio of biomass in each area weighted by ratio to Bstar, use 1-ratio of bio
            /// because want to weight T and make more fish move to area with lower bio compared to Bstar
            /// idea is that if B/Bstar<1 then not densely populated and more fish would move there
            
                    if(move_switch==8)
                     {
                      Fract_Move_DD(j,r,y,a)=((1-input_residency(j,r,a))/(1+A(j,r)*mfexp(c(j,r)*biomass_BM_age(j,r,y,a))));
       
                      biomass_BM_temp=0;
                      biomass_BM_temp2=0;
                       for (int s=1;s<=npops;s++)
                        {
                         for (int n=1;n<=nregions(s);n++)
                          {       
                           biomass_BM_temp(s,n)=biomass_BM_age(s,n,y,a)/Bstar(s,n);
                          }
                        }
                       biomass_BM_temp2=sum(biomass_BM_temp)-(biomass_BM_age(j,r,y,a)/Bstar(j,r)); //do not include population/region moving from in summation
                        for (int s=1;s<=npops;s++)
                         {
                          for (int n=1;n<=nregions(s);n++)
                           {
                            if(j==s && r==n) //do not include current pop/region in calcs (residency is already defined)
                             {
                              rel_bio(j,r,y,a,s,n)=0;  //rel bio defined for movement out of pop j region r as suitability of destination population s, region n
                             }
                            if(j!=s || r!=n) 
                             {
                              rel_bio(j,r,y,a,s,n)=1-((biomass_BM_temp(s,n))/(biomass_BM_temp2));
                             }
                            if(sum(nregions)==2)
                             {
                              rel_bio(j,r,y,a,s,n)=1;
                             }
                            }
                           }
                       for (int s=1;s<=npops;s++)
                        {
                         for (int n=1;n<=nregions(s);n++)
                          {
                           if(j==s && r==n) 
                            {
                             T(j,r,y,a,s,n)=1-Fract_Move_DD(j,r,y,a);
                            }
                           if(j!=s || r!=n) 
                            {
                             T(j,r,y,a,s,n)=rel_bio(j,r,y,a,s,n)*Fract_Move_DD(j,r,y,a);
                            }
                          }
                        }
                    }
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

                abundance_move_overlap_temp=0;

                for (int k=1;k<=npops;k++)
                 {
                  for (int n=1;n<=nregions(k);n++)
                   {
                    if(move_switch!=6  || move_switch!=7  ||a==1)
                     {
                      abundance_move_overlap_temp(k,n)=abundance_at_age_AM_overlap_region(p,k,y-1,a-1,n)*mfexp(-(M(k,n,y-1,a-1)+F(k,n,y-1,a-1))*(1-tspawn(p)))*T(p,n,y,a,j,r); //with overlap always use natal population movement rates
                     }
                    if(move_switch==6 && a>1)
                     {
                      if(a==return_age && p==j && p==k && j==k)
                      {
                       abundance_move_overlap_temp(k,n)=0; //with overlap always use natal population movement rates
                      }
                      if(a==return_age && p==j && j!=k)
                      {
                       abundance_move_overlap_temp(k,n)=abundance_at_age_AM_overlap_region(p,k,y-1,a-1,n)*mfexp(-(M(k,n,y-1,a-1)+F(k,n,y-1,a-1))*(1-tspawn(p)))*return_probability(p); //with overlap always use natal population movement rates
                      }
                     }
                   }
                  }
                    if(move_switch!=6 || move_switch!=7  || a==1)
                     {
                        abundance_at_age_AM_overlap_region(p,j,y,a,r)=sum(abundance_move_overlap_temp);
                     }
                    if(move_switch==7)  //all fish stay where they were (i.e., no return migration)
                     {
                        abundance_at_age_AM_overlap_region(p,j,y,a,r)=abundance_at_age_AM_overlap_region(p,j,y-1,a-1,r)*mfexp(-(M(j,r,y-1,a-1)+F(j,r,y-1,a-1))*(1-tspawn(p)));
                     }
                    if(move_switch==6 && a>1)
                     {
                      if(a<return_age || a>return_age)
                       {
                        abundance_at_age_AM_overlap_region(p,j,y,a,r)=abundance_at_age_AM_overlap_region(p,j,y-1,a-1,r)*mfexp(-(M(j,r,y-1,a-1)+F(j,r,y-1,a-1))*(1-tspawn(p))); //with overlap always use natal population movement rates                     
                       }
                      if(a==return_age && p==j)
                       {
                        abundance_at_age_AM_overlap_region(p,j,y,a,r)=abundance_at_age_AM_overlap_region(p,j,y-1,a-1,r)*mfexp(-(M(j,r,y-1,a-1)+F(j,r,y-1,a-1))*(1-tspawn(p)))+(sum(abundance_move_overlap_temp)/nregions(p));
                       }
                      if(a==return_age && p!=j)
                       {
                        abundance_at_age_AM_overlap_region(p,j,y,a,r)=(1-return_probability(p))*abundance_at_age_AM_overlap_region(p,j,y-1,a-1,r)*mfexp(-(M(j,r,y-1,a-1)+F(j,r,y-1,a-1))*(1-tspawn(p)));
                       }
                      }
                abundance_AM_overlap_region_all_natal_temp(j,r,y,a,p)=abundance_at_age_AM_overlap_region(p,j,y,a,r);
                biomass_AM_overlap_region_all_natal_temp(j,r,y,a,p)=abundance_at_age_AM_overlap_region(p,j,y,a,r)*weight_population(p,r,y,a);
                abundance_AM_overlap_region_all_natal(j,r,y,a)=sum(abundance_AM_overlap_region_all_natal_temp(j,r,y,a));
                biomass_AM_overlap_age_region_all_natal(j,r,y,a)=sum(biomass_AM_overlap_region_all_natal_temp(j,r,y,a));
                biomass_AM_overlap_region_all_natal(j,r,y)=sum(biomass_AM_overlap_age_region_all_natal(j,r,y));
                abundance_at_age_AM_overlap_population(p,j,y,a)=sum(abundance_at_age_AM_overlap_region(p,j,y,a));
                biomass_AM_age_overlap(p,j,r,y,a)=weight_population(p,r,y,a)*abundance_at_age_AM_overlap_region(p,j,y,a,r);
                biomass_AM_overlap_region(p,j,r,y)=sum(biomass_AM_age_overlap(p,j,r,y));
                biomass_population_temp_overlap(p,j,y,r)=biomass_AM_overlap_region(p,j,r,y);
                biomass_population_overlap(p,j,y)=sum(biomass_population_temp_overlap(p,j,y));
                biomass_natal_temp_overlap(p,y,j)=biomass_population_overlap(p,j,y);
                biomass_natal_overlap(p,y)=sum(biomass_natal_temp_overlap(p,y));

 //////////////////////////////////////////////////////////////////////////////
  //////////////////////////////////////////////////////////////////////////////
   ///////////////NON-NATAL Homing movement calcs and putting natal homing abundance into area abundance///////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////
    

                    abundance_move_temp=0;
                     bio_move_temp=0;

                for (int k=1;k<=npops;k++)
                 {
                  for (int n=1;n<=nregions(k);n++)
                   {
                     abundance_move_temp(k,n)=abundance_at_age_AM(k,n,y-1,a-1)*mfexp(-(M(k,n,y-1,a-1)+F(k,n,y-1,a-1))*(1-tspawn(k)))*T(k,n,y,a,j,r);
                     bio_move_temp(k,n)=abundance_move_temp(k,n)*weight_population(k,n,y,a);
                   }
                  }

                  if(natal_homing_switch>0)
                   {                  
                    abundance_at_age_AM(j,r,y,a)=abundance_AM_overlap_region_all_natal(j,r,y,a);
                    biomass_AM(j,r,y)= biomass_AM_overlap_region_all_natal(j,r,y);                  
                   }
                  if(natal_homing_switch==0)
                   {
                    abundance_at_age_AM(j,r,y,a)=sum(abundance_move_temp);
                    biomass_AM_age(j,r,y,a)=weight_population(j,r,y,a)*abundance_at_age_AM(j,r,y,a);
                    biomass_AM(j,r,y)=sum(biomass_AM_age(j,r,y));
                   }

                biomass_population_temp(j,y,r)=biomass_AM(j,r,y);
                biomass_population(j,y)=sum(biomass_population_temp(j,y));
                biomass_total_temp(y,j)=biomass_population(j,y);
                biomass_total(y)=sum(biomass_total_temp(y));

                   abundance_in(j,r,y,a)=sum(abundance_move_temp)-abundance_move_temp(j,r);
                   abundance_res(j,r,y,a)=abundance_move_temp(j,r);
                   abundance_leave(j,r,y,a)=abundance_at_age_BM(j,r,y,a)-abundance_res(j,r,y,a);
                   bio_in(j,r,y,a)=sum(bio_move_temp)-bio_move_temp(j,r);
                   bio_res(j,r,y,a)=bio_move_temp(j,r);
                   bio_leave(j,r,y,a)=abundance_at_age_BM(j,r,y,a)*weight_population(j,r,y,a)-bio_res(j,r,y,a);
             }
            }
           }
          }
         }//end a==2 if statement

 ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
       if(a>2 && a<nages)
        {
           for (int p=1;p<=npops;p++)
            {
             for (int j=1;j<=npops;j++)
              {
               for (int r=1;r<=nregions(j);r++)
                {
                 for (int z=1;z<=nfleets(j);z++)
                  {
                  abundance_at_age_BM_overlap_region(p,j,y,a,r)=abundance_at_age_AM_overlap_region(p,j,y-1,a-1,r)*mfexp(-(M(j,r,y-1,a-1)+F(j,r,y-1,a-1)));
                  abundance_at_age_BM_overlap_population(p,j,y,a)=sum(abundance_at_age_BM_overlap_region(p,j,y,a));
                  biomass_BM_age_overlap(p,j,r,y,a)=weight_population(p,r,y,a)*abundance_at_age_BM_overlap_region(p,j,y,a,r);
                  biomass_BM_overlap_region(p,j,r,y)=sum(biomass_BM_age_overlap(p,j,r,y));

/////////////////////////metapop/////////////////////////////////////////////////////////
                 abundance_at_age_BM(j,r,y,a)=abundance_at_age_AM(j,r,y-1,a-1)*mfexp(-(M(j,r,y-1,a-1)+F(j,r,y-1,a-1)));
/////////////////////////////////////////////////////////////////////////////////////////

                  if(natal_homing_switch==0)
                   {
                    biomass_BM_age(j,r,y,a)=weight_population(j,r,y,a)*abundance_at_age_BM(j,r,y,a);
                    biomass_BM(j,r,y)=sum(biomass_BM_age(j,r,y));
                   }
                  if(natal_homing_switch>0) //if natal homing put abundance summed across natal population by region into abundance at age AM
                   {
                    biomass_BM_overlap_temp(j,r,y,a,p)=biomass_BM_age_overlap(p,j,r,y,a);
                    biomass_BM_age(j,r,y,a)=sum(biomass_BM_overlap_temp(j,r,y,a));
                    biomass_BM(j,r,y)=sum(biomass_BM_age(j,r,y));
                   }
              }
             }
            }
           }
          } //close loops so have full biomass vectors filled in at start of DD movement calcs
       if(a>2 && a<nages)
        {
           for (int p=1;p<=npops;p++)
            {
             for (int j=1;j<=npops;j++)
              {
               for (int r=1;r<=nregions(j);r++)
                {
                 for (int z=1;z<=nfleets(j);z++)
                  {
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////Density-Dependent Movement Calcs///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
           /// rel_bio gives ratio of biomass in each area weighted by ratio to Bstar, use 1-ratio of bio
            /// because want to weight T and make more fish move to area with lower bio compared to Bstar
            /// idea is that if B/Bstar<1 then not densely populated and more fish would move there
            
                    if(move_switch==8)
                     {
                      Fract_Move_DD(j,r,y,a)=((1-input_residency(j,r,a))/(1+A(j,r)*mfexp(c(j,r)*biomass_BM_age(j,r,y,a))));
       
                      biomass_BM_temp=0;
                      biomass_BM_temp2=0;
                       for (int s=1;s<=npops;s++)
                        {
                         for (int n=1;n<=nregions(s);n++)
                          {       
                           biomass_BM_temp(s,n)=biomass_BM_age(s,n,y,a)/Bstar(s,n);
                          }
                        }
                       biomass_BM_temp2=sum(biomass_BM_temp)-(biomass_BM_age(j,r,y,a)/Bstar(j,r)); //do not include population/region moving from in summation
                        for (int s=1;s<=npops;s++)
                         {
                          for (int n=1;n<=nregions(s);n++)
                           {
                            if(j==s && r==n) //do not include current pop/region in calcs (residency is already defined)
                             {
                              rel_bio(j,r,y,a,s,n)=0;  //rel bio defined for movement out of pop j region r as suitability of destination population s, region n
                             }
                            if(j!=s || r!=n) 
                             {
                              rel_bio(j,r,y,a,s,n)=1-((biomass_BM_temp(s,n))/(biomass_BM_temp2));
                             }
                            if(sum(nregions)==2)
                             {
                              rel_bio(j,r,y,a,s,n)=1;
                             }
                            }
                           }
                       for (int s=1;s<=npops;s++)
                        {
                         for (int n=1;n<=nregions(s);n++)
                          {
                           if(j==s && r==n) 
                            {
                             T(j,r,y,a,s,n)=1-Fract_Move_DD(j,r,y,a);
                            }
                           if(j!=s || r!=n) 
                            {
                             T(j,r,y,a,s,n)=rel_bio(j,r,y,a,s,n)*Fract_Move_DD(j,r,y,a);
                            }
                          }
                        }
                    }
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

                abundance_move_overlap_temp=0;

                for (int k=1;k<=npops;k++)
                 {
                  for (int n=1;n<=nregions(k);n++)
                   {
                    if(move_switch!=6  || move_switch!=7 || a==1)
                     {
                      abundance_move_overlap_temp(k,n)=abundance_at_age_AM_overlap_region(p,k,y-1,a-1,n)*mfexp(-(M(k,n,y-1,a-1)+F(k,n,y-1,a-1)))*T(p,n,y,a,j,r); //with overlap always use natal population movement rates
                     }
                    if(move_switch==6 && a>1)
                     {
                      if(a==return_age && p==j && p==k && j==k)
                      {
                       abundance_move_overlap_temp(k,n)=0; //with overlap always use natal population movement rates
                      }
                      if(a==return_age && p==j && j!=k)
                      {
                       abundance_move_overlap_temp(k,n)=abundance_at_age_AM_overlap_region(p,k,y-1,a-1,n)*mfexp(-(M(k,n,y-1,a-1)+F(k,n,y-1,a-1)))*return_probability(p); //with overlap always use natal population movement rates
                      }
                     }
                   }
                  }
                    if(move_switch!=6 || move_switch!=7  || a==1)
                     {
                        abundance_at_age_AM_overlap_region(p,j,y,a,r)=sum(abundance_move_overlap_temp);
                     }
                    if(move_switch==7)  //all fish stay where they were (i.e., no return migration)
                     {
                        abundance_at_age_AM_overlap_region(p,j,y,a,r)=abundance_at_age_AM_overlap_region(p,j,y-1,a-1,r)*mfexp(-(M(j,r,y-1,a-1)+F(j,r,y-1,a-1)));
                     }
                    if(move_switch==6 && a>1)
                     {
                      if(a<return_age || a>return_age)
                       {
                        abundance_at_age_AM_overlap_region(p,j,y,a,r)=abundance_at_age_AM_overlap_region(p,j,y-1,a-1,r)*mfexp(-(M(j,r,y-1,a-1)+F(j,r,y-1,a-1))); //with overlap always use natal population movement rates                     
                       }
                      if(a==return_age && p==j)
                       {
                        abundance_at_age_AM_overlap_region(p,j,y,a,r)=abundance_at_age_AM_overlap_region(p,j,y-1,a-1,r)*mfexp(-(M(j,r,y-1,a-1)+F(j,r,y-1,a-1)))+(sum(abundance_move_overlap_temp)/nregions(p));
                       }
                      if(a==return_age && p!=j)
                       {
                        abundance_at_age_AM_overlap_region(p,j,y,a,r)=(1-return_probability(p))*abundance_at_age_AM_overlap_region(p,j,y-1,a-1,r)*mfexp(-(M(j,r,y-1,a-1)+F(j,r,y-1,a-1)));
                       }
                      }
                abundance_AM_overlap_region_all_natal_temp(j,r,y,a,p)=abundance_at_age_AM_overlap_region(p,j,y,a,r);
                biomass_AM_overlap_region_all_natal_temp(j,r,y,a,p)=abundance_at_age_AM_overlap_region(p,j,y,a,r)*weight_population(p,r,y,a);
                abundance_AM_overlap_region_all_natal(j,r,y,a)=sum(abundance_AM_overlap_region_all_natal_temp(j,r,y,a));
                biomass_AM_overlap_age_region_all_natal(j,r,y,a)=sum(biomass_AM_overlap_region_all_natal_temp(j,r,y,a));
                biomass_AM_overlap_region_all_natal(j,r,y)=sum(biomass_AM_overlap_age_region_all_natal(j,r,y));
                abundance_at_age_AM_overlap_population(p,j,y,a)=sum(abundance_at_age_AM_overlap_region(p,j,y,a));
                biomass_AM_age_overlap(p,j,r,y,a)=weight_population(p,r,y,a)*abundance_at_age_AM_overlap_region(p,j,y,a,r);
                biomass_AM_overlap_region(p,j,r,y)=sum(biomass_AM_age_overlap(p,j,r,y));
                biomass_population_temp_overlap(p,j,y,r)=biomass_AM_overlap_region(p,j,r,y);
                biomass_population_overlap(p,j,y)=sum(biomass_population_temp_overlap(p,j,y));
                biomass_natal_temp_overlap(p,y,j)=biomass_population_overlap(p,j,y);
                biomass_natal_overlap(p,y)=sum(biomass_natal_temp_overlap(p,y));
                
 //////////////////////////////////////////////////////////////////////////////
  //////////////////////////////////////////////////////////////////////////////
   ///////////////NON-NATAL Homing movement calcs and putting natal homing abundance into area abundance///////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////
    

                   abundance_move_temp=0;
                   bio_move_temp=0;

                for (int k=1;k<=npops;k++)
                 {
                  for (int n=1;n<=nregions(k);n++)
                   {
                     abundance_move_temp(k,n)=abundance_at_age_AM(k,n,y-1,a-1)*mfexp(-(M(k,n,y-1,a-1)+F(k,n,y-1,a-1)))*T(k,n,y,a,j,r);
                     bio_move_temp(k,n)=abundance_move_temp(k,n)*weight_population(k,n,y,a);
                   }
                  }
                  
                  if(natal_homing_switch>0)
                   {
                    abundance_at_age_AM(j,r,y,a)=abundance_AM_overlap_region_all_natal(j,r,y,a);
                    biomass_AM(j,r,y)= biomass_AM_overlap_region_all_natal(j,r,y);
                   }
                  if(natal_homing_switch==0)
                   {
                    abundance_at_age_AM(j,r,y,a)=sum(abundance_move_temp);
                    biomass_AM_age(j,r,y,a)=weight_population(j,r,y,a)*abundance_at_age_AM(j,r,y,a);
                    biomass_AM(j,r,y)=sum(biomass_AM_age(j,r,y));
                   }

                biomass_population_temp(j,y,r)=biomass_AM(j,r,y);
                biomass_population(j,y)=sum(biomass_population_temp(j,y));
                biomass_total_temp(y,j)=biomass_population(j,y);
                biomass_total(y)=sum(biomass_total_temp(y));

                abundance_in(j,r,y,a)=sum(abundance_move_temp)-abundance_move_temp(j,r);
                abundance_res(j,r,y,a)=abundance_move_temp(j,r);
                abundance_leave(j,r,y,a)=abundance_at_age_BM(j,r,y,a)-abundance_res(j,r,y,a);
                bio_in(j,r,y,a)=sum(bio_move_temp)-bio_move_temp(j,r);
                bio_res(j,r,y,a)=bio_move_temp(j,r);
                bio_leave(j,r,y,a)=abundance_at_age_BM(j,r,y,a)*weight_population(j,r,y,a)-bio_res(j,r,y,a);
           }
          }
         }
        }
       }//end a>2 <nages if statement

 ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
       if(a==nages) //account for fish already in plus group
        {
          for (int p=1;p<=npops;p++)
            {
             for (int j=1;j<=npops;j++)
              {
               for (int r=1;r<=nregions(j);r++)
                {
                 for (int z=1;z<=nfleets(j);z++)
                  {
                  abundance_at_age_BM_overlap_region(p,j,y,a,r)=abundance_at_age_AM_overlap_region(p,j,y-1,a-1,r)*mfexp(-(M(j,r,y-1,a-1)+F(j,r,y-1,a-1)))+abundance_at_age_AM_overlap_region(p,j,y-1,a,r)*mfexp(-(M(j,r,y-1,a)+F(j,r,y-1,a)));
                  abundance_at_age_BM_overlap_population(p,j,y,a)=sum(abundance_at_age_BM_overlap_region(p,j,y,a));
                  biomass_BM_age_overlap(p,j,r,y,a)=weight_population(p,r,y,a)*abundance_at_age_BM_overlap_region(p,j,y,a,r);
                  biomass_BM_overlap_region(p,j,r,y)=sum(biomass_BM_age_overlap(p,j,r,y));
                
/////////////////////////metapop/////////////////////////////////////////////////////////
               abundance_at_age_BM(j,r,y,a)=abundance_at_age_AM(j,r,y-1,a-1)*mfexp(-(M(j,r,y-1,a-1)+F(j,r,y-1,a-1)))+abundance_at_age_AM(j,r,y-1,a)*mfexp(-(M(j,r,y-1,a)+F(j,r,y-1,a)));
/////////////////////////////////////////////////////////////////////////////////////////

                  if(natal_homing_switch==0)
                   {
                    biomass_BM_age(j,r,y,a)=weight_population(j,r,y,a)*abundance_at_age_BM(j,r,y,a);
                    biomass_BM(j,r,y)=sum(biomass_BM_age(j,r,y));
                   }
                  if(natal_homing_switch>0) //if natal homing put abundance summed across natal population by region into abundance at age AM
                   {
                    biomass_BM_overlap_temp(j,r,y,a,p)=biomass_BM_age_overlap(p,j,r,y,a);
                    biomass_BM_age(j,r,y,a)=sum(biomass_BM_overlap_temp(j,r,y,a));
                    biomass_BM(j,r,y)=sum(biomass_BM_age(j,r,y));
                   }
              }
             }
            }
           }
          } //close loops so have full biomass vectors filled in at start of DD movement calcs
       if(a==nages) //account for fish already in plus group
        {
           for (int p=1;p<=npops;p++)
            {
             for (int j=1;j<=npops;j++)
              {
               for (int r=1;r<=nregions(j);r++)
                {
                 for (int z=1;z<=nfleets(j);z++)
                  {
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////Density-Dependent Movement Calcs///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
           /// rel_bio gives ratio of biomass in each area weighted by ratio to Bstar, use 1-ratio of bio
            /// because want to weight T and make more fish move to area with lower bio compared to Bstar
            /// idea is that if B/Bstar<1 then not densely populated and more fish would move there
            
                    if(move_switch==8)
                     {
                      Fract_Move_DD(j,r,y,a)=((1-input_residency(j,r,a))/(1+A(j,r)*mfexp(c(j,r)*biomass_BM_age(j,r,y,a))));
       
                      biomass_BM_temp=0;
                      biomass_BM_temp2=0;
                       for (int s=1;s<=npops;s++)
                        {
                         for (int n=1;n<=nregions(s);n++)
                          {       
                           biomass_BM_temp(s,n)=biomass_BM_age(s,n,y,a)/Bstar(s,n);
                          }
                        }
                       biomass_BM_temp2=sum(biomass_BM_temp)-(biomass_BM_age(j,r,y,a)/Bstar(j,r)); //do not include population/region moving from in summation
                        for (int s=1;s<=npops;s++)
                         {
                          for (int n=1;n<=nregions(s);n++)
                           {
                            if(j==s && r==n) //do not include current pop/region in calcs (residency is already defined)
                             {
                              rel_bio(j,r,y,a,s,n)=0;  //rel bio defined for movement out of pop j region r as suitability of destination population s, region n
                             }
                            if(j!=s || r!=n) 
                             {
                              rel_bio(j,r,y,a,s,n)=1-((biomass_BM_temp(s,n))/(biomass_BM_temp2));
                             }
                            if(sum(nregions)==2)
                             {
                              rel_bio(j,r,y,a,s,n)=1;
                             }
                            }
                           }
                       for (int s=1;s<=npops;s++)
                        {
                         for (int n=1;n<=nregions(s);n++)
                          {
                           if(j==s && r==n) 
                            {
                             T(j,r,y,a,s,n)=1-Fract_Move_DD(j,r,y,a);
                            }
                           if(j!=s || r!=n) 
                            {
                             T(j,r,y,a,s,n)=rel_bio(j,r,y,a,s,n)*Fract_Move_DD(j,r,y,a);
                            }
                          }
                        }
                    }
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

                abundance_move_overlap_temp=0;

                for (int k=1;k<=npops;k++)
                 {
                  for (int n=1;n<=nregions(k);n++)
                   {
                    if(move_switch!=6  || move_switch!=7  || a==1)
                     {
                      abundance_move_overlap_temp(k,n)=abundance_at_age_AM_overlap_region(p,k,y-1,a-1,n)*mfexp(-(M(k,n,y-1,a-1)+F(k,n,y-1,a-1)))*T(p,n,y,a,j,r)+abundance_at_age_AM_overlap_region(p,k,y-1,a,n)*mfexp(-(M(k,n,y-1,a)+F(k,n,y-1,a)))*T(p,n,y,a,j,r); //with overlap always use natal population movement rates
                     }
                    if(move_switch==6 && a>1)
                     {
                      if(a==return_age && p==j && p==k && j==k)
                      {
                       abundance_move_overlap_temp(k,n)=0; //with overlap always use natal population movement rates
                      }
                      if(a==return_age && p==j && j!=k)
                      {
                       abundance_move_overlap_temp(k,n)=abundance_at_age_AM_overlap_region(p,k,y-1,a-1,n)*mfexp(-(M(k,n,y-1,a-1)+F(k,n,y-1,a-1)))*return_probability(p)+abundance_at_age_AM_overlap_region(p,k,y-1,a,n)*mfexp(-(M(k,n,y-1,a)+F(k,n,y-1,a)))*return_probability(p); //with overlap always use natal population movement rates
                      }
                     }
                   }
                  }
                    if(move_switch!=6 || move_switch!=7  || a==1)
                     {
                        abundance_at_age_AM_overlap_region(p,j,y,a,r)=sum(abundance_move_overlap_temp);
                     }
                    if(move_switch==7)  //all fish stay where they were (i.e., no return migration)
                     {
                        abundance_at_age_AM_overlap_region(p,j,y,a,r)=abundance_at_age_AM_overlap_region(p,j,y-1,a-1,r)*mfexp(-(M(j,r,y-1,a-1)+F(j,r,y-1,a-1)))+abundance_at_age_AM_overlap_region(p,j,y-1,a,r)*mfexp(-(M(j,r,y-1,a)+F(j,r,y-1,a)));
                     }
                    if(move_switch==6 && a>1)
                     {
                      if(a<return_age || a>return_age)
                       {
                        abundance_at_age_AM_overlap_region(p,j,y,a,r)=abundance_at_age_AM_overlap_region(p,j,y-1,a-1,r)*mfexp(-(M(j,r,y-1,a-1)+F(j,r,y-1,a-1)))+abundance_at_age_AM_overlap_region(p,j,y-1,a,r)*mfexp(-(M(j,r,y-1,a)+F(j,r,y-1,a))); //with overlap always use natal population movement rates                     
                       }
                      if(a==return_age && p==j)
                       {
                        abundance_at_age_AM_overlap_region(p,j,y,a,r)=abundance_at_age_AM_overlap_region(p,j,y-1,a-1,r)*mfexp(-(M(j,r,y-1,a-1)+F(j,r,y-1,a-1)))+abundance_at_age_AM_overlap_region(p,j,y-1,a,r)*mfexp(-(M(j,r,y-1,a)+F(j,r,y-1,a)))+(sum(abundance_move_overlap_temp)/nregions(p));
                       }
                      if(a==return_age && p!=j)
                       {
                        abundance_at_age_AM_overlap_region(p,j,y,a,r)=(1-return_probability(p))*abundance_at_age_AM_overlap_region(p,j,y-1,a-1,r)*mfexp(-(M(j,r,y-1,a-1)+F(j,r,y-1,a-1)))+(1-return_probability(p))*abundance_at_age_AM_overlap_region(p,j,y-1,a,r)*mfexp(-(M(j,r,y-1,a)+F(j,r,y-1,a)));
                       }
                      }
                abundance_AM_overlap_region_all_natal_temp(j,r,y,a,p)=abundance_at_age_AM_overlap_region(p,j,y,a,r);
                biomass_AM_overlap_region_all_natal_temp(j,r,y,a,p)=abundance_at_age_AM_overlap_region(p,j,y,a,r)*weight_population(p,r,y,a);
                abundance_AM_overlap_region_all_natal(j,r,y,a)=sum(abundance_AM_overlap_region_all_natal_temp(j,r,y,a));
                biomass_AM_overlap_age_region_all_natal(j,r,y,a)=sum(biomass_AM_overlap_region_all_natal_temp(j,r,y,a));
                biomass_AM_overlap_region_all_natal(j,r,y)=sum(biomass_AM_overlap_age_region_all_natal(j,r,y));
                abundance_at_age_AM_overlap_population(p,j,y,a)=sum(abundance_at_age_AM_overlap_region(p,j,y,a));
                biomass_AM_age_overlap(p,j,r,y,a)=weight_population(p,r,y,a)*abundance_at_age_AM_overlap_region(p,j,y,a,r);
                biomass_AM_overlap_region(p,j,r,y)=sum(biomass_AM_age_overlap(p,j,r,y));
                biomass_population_temp_overlap(p,j,y,r)=biomass_AM_overlap_region(p,j,r,y);
                biomass_population_overlap(p,j,y)=sum(biomass_population_temp_overlap(p,j,y));
                biomass_natal_temp_overlap(p,y,j)=biomass_population_overlap(p,j,y);
                biomass_natal_overlap(p,y)=sum(biomass_natal_temp_overlap(p,y));

 //////////////////////////////////////////////////////////////////////////////
  //////////////////////////////////////////////////////////////////////////////
   ///////////////NON-NATAL Homing movement calcs and putting natal homing abundance into area abundance///////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////
    
                  
                   abundance_move_temp=0;
                   bio_move_temp=0;

                for (int k=1;k<=npops;k++)
                 {
                  for (int n=1;n<=nregions(k);n++)
                   {
                     abundance_move_temp(k,n)=abundance_at_age_AM(k,n,y-1,a-1)*mfexp(-(M(k,n,y-1,a-1)+F(k,n,y-1,a-1)))*T(k,n,y,a,j,r)+abundance_at_age_AM(k,n,y-1,a)*mfexp(-(M(k,n,y-1,a)+F(k,n,y-1,a)))*T(k,n,y,a,j,r);;
                     bio_move_temp(k,n)=abundance_move_temp(k,n)*weight_population(k,n,y,a);
                   }
                  }
                  if(natal_homing_switch>0)
                   {
                    abundance_at_age_AM(j,r,y,a)=abundance_AM_overlap_region_all_natal(j,r,y,a);
                    biomass_AM(j,r,y)= biomass_AM_overlap_region_all_natal(j,r,y);
                   }
                  if(natal_homing_switch==0)
                   {
                    abundance_at_age_AM(j,r,y,a)=sum(abundance_move_temp);
                    biomass_AM_age(j,r,y,a)=weight_population(j,r,y,a)*abundance_at_age_AM(j,r,y,a);
                    biomass_AM(j,r,y)=sum(biomass_AM_age(j,r,y));
                   }

                biomass_population_temp(j,y,r)=biomass_AM(j,r,y);
                biomass_population(j,y)=sum(biomass_population_temp(j,y));
                biomass_total_temp(y,j)=biomass_population(j,y);
                biomass_total(y)=sum(biomass_total_temp(y));

                   abundance_in(j,r,y,a)=sum(abundance_move_temp)-abundance_move_temp(j,r);
                   abundance_res(j,r,y,a)=abundance_move_temp(j,r);
                   abundance_leave(j,r,y,a)=abundance_at_age_BM(j,r,y,a)-abundance_res(j,r,y,a);
                   bio_in(j,r,y,a)=sum(bio_move_temp)-bio_move_temp(j,r);
                   bio_res(j,r,y,a)=bio_move_temp(j,r);
                   bio_leave(j,r,y,a)=abundance_at_age_BM(j,r,y,a)*weight_population(j,r,y,a)-bio_res(j,r,y,a);
            }
           }
          }
         }
        } //end nages if statement

           for (int p=1;p<=npops;p++)
            {
             for (int j=1;j<=npops;j++)
              {
               for (int r=1;r<=nregions(j);r++)
                {
                 for (int z=1;z<=nfleets_survey(j);z++)    /// survey index  1. Currently set up for more than 1 survey fleet
                  {
                   if(tsurvey(j,r)==0) //if survey at beggining of year, do calcs without temporal adjustment for mortality
                   {
                  true_survey_fleet_overlap_age(p,j,r,y,z,a)=survey_selectivity(j,r,y,a,z)*abundance_at_age_AM_overlap_region(p,j,y,a,r)*q_survey(j,r,z);
                  true_survey_fleet_overlap_age_bio(p,j,r,y,z,a)=true_survey_fleet_overlap_age(p,j,r,y,z,a)*weight_population(p,r,y,a);
                  true_survey_fleet_bio_overlap(p,j,r,y,z)=sum(true_survey_fleet_overlap_age_bio(p,j,r,y,z));  
                  true_survey_fleet_bio_overlap_temp(j,r,y,z,p)=true_survey_fleet_bio_overlap(p,j,r,y,z);
                  OBS_survey_fleet_bio_overlap(p,j,r,y,z)=true_survey_fleet_bio_overlap(p,j,r,y,z)*mfexp(survey_RN_overlap(p,j,r,y,z)*sigma_survey_overlap(p,j,r,z)-.5*square(sigma_survey_overlap(p,j,r,z)));
                  OBS_survey_fleet_bio_temp(j,r,y,z,p)=OBS_survey_fleet_bio_overlap(p,j,r,y,z);

                if(natal_homing_switch==0)
                 {
                  true_survey_fleet_age(j,r,y,z,a)=survey_selectivity(j,r,y,a,z)*abundance_at_age_AM(j,r,y,a)*q_survey(j,r,z);
                  true_survey_fleet_age_bio(j,r,y,z,a)=true_survey_fleet_age(j,r,y,z,a)*weight_population(j,r,y,a);                  
                  true_survey_fleet_bio(j,r,y,z)=sum(true_survey_fleet_age_bio(j,r,y,z));
                  OBS_survey_fleet_bio(j,r,y,z)=true_survey_fleet_bio(j,r,y,z)*mfexp(survey_RN(j,r,y,z)*sigma_survey(j,r,z)-.5*square(sigma_survey(j,r,z)));
                 }
                if(natal_homing_switch==1)
                 {
                  true_survey_fleet_bio(j,r,y,z)=sum(true_survey_fleet_bio_overlap_temp(j,r,y,z));
                  OBS_survey_fleet_bio(j,r,y,z)=sum(OBS_survey_fleet_bio_temp(j,r,y,z));  
                 }
             
                  true_survey_region_bio_overlap(p,j,y,r)=sum(true_survey_fleet_bio_overlap(p,j,r,y));               
                  true_survey_population_bio_overlap(p,y,j)=sum(true_survey_region_bio_overlap(p,j,y));               
                  true_survey_natal_bio_overlap(y,p)=sum(true_survey_population_bio_overlap(p,y));               
                  true_survey_total_bio_overlap(y)=sum(true_survey_natal_bio_overlap(y));
                  OBS_survey_region_bio_overlap(p,j,y,r)=sum(OBS_survey_fleet_bio_overlap(p,j,r,y));
                  OBS_survey_population_bio_overlap(p,y,j)=sum(OBS_survey_region_bio_overlap(p,j,y));
                  OBS_survey_natal_bio_overlap(y,p)=sum(OBS_survey_population_bio_overlap(p,y));
                  OBS_survey_total_bio_overlap(y)=sum(OBS_survey_natal_bio_overlap(y));
                  
                  true_survey_region_bio(j,y,r)=sum(true_survey_fleet_bio(j,r,y));
                  true_survey_population_bio(y,j)=sum(true_survey_region_bio(j,y));
                  true_survey_total_bio(y)=sum(true_survey_population_bio(y));
                  OBS_survey_region_bio(j,y,r)=sum(OBS_survey_fleet_bio(j,r,y));
                  OBS_survey_population_bio(y,j)=sum(OBS_survey_region_bio(j,y));
                  OBS_survey_total_bio(y)=sum(OBS_survey_population_bio(y));

                  apport_region_survey_biomass(j,r,y)=OBS_survey_region_bio(j,y,r)/OBS_survey_population_bio(y,j);
                  
                } //tsurvey==0
               } //end survey_fleets 
      }
     }
    }
   } //end age loop
 ///////////////////////////////////////////////////////////////////////////////////
 ///////////////////////////////////////////////////////////////////////////////////
 /////////////////NEWTON RAPHSON CALCS//////////////////////////////////////////////////////////////////
 ///////////////////////////////////////////////////////////////////////////////////
 ///////////////////////////////////////////////////////////////////////////////////
           for (int p=1;p<=npops;p++)
            {
             for (int j=1;j<=npops;j++)
              {
               for (int r=1;r<=nregions(j);r++)
                {
                   if(model_type_switch>0)  //Find the fully selected F that would result in the TAC
                     {
                      for (int a=1;a<=nages;a++)
                       {
                         for(int x=1;x<=nfleets(j);x++)
                           {
                             if(model_type_switch==1)
                                {
                                 if(natal_homing_switch>0)
                                   {
                                               if(parse_TAC==0) //use input TAC
                                                {
                                                  if(calc_TAC_from_uMSY==0)
                                                   {
                                                    TAC(j,r,x,y)=input_TAC(j,r,x);
                                                   }
                                                   if(calc_TAC_from_uMSY==1)
                                                   {
                                                    TAC(j,r,x,y)=input_u(j,r,x)*biomass_population(j,y);
                                                   }
                                                   if(calc_TAC_from_uMSY==2)
                                                   {
                                                    TAC(j,r,x,y)=input_u(j,r,x)*biomass_AM(j,r,y);
                                                   }
                                                }
                                             if(parse_TAC==1) //use observed data to parse input_TAC by region // if multiple fleets then evenly distribute across fleets
                                                {
                                                 if(parse_TAC_source==0)
                                                  {
                                                  if(calc_TAC_from_uMSY==0)
                                                   {
                                                   if(y==1)
                                                    {
                                                     TAC(j,r,x,y)=input_TAC(j,r,x)/(nregions(j)*nfleets(j)); //partition evenly by total fleets in area
                                                    }
                                                   if(y>1) //assume rec index occurs at time of spawning so never have available in current year
                                                    {
                                                     TAC(j,r,x,y)=rec_index_prop_BM(j,r,y-1)*input_TAC(j,r,x)/nfleets(j); //partition regional quota evenly by fleets in region
                                                    }
                                                   }
                                                  if(calc_TAC_from_uMSY==1)
                                                   {
                                                   if(y==1)
                                                    {
                                                     TAC(j,r,x,y)=input_u(j,r,x)*biomass_population(j,y)/(nregions(j)*nfleets(j)); //partition evenly by total fleets in area
                                                    }
                                                   if(y>1) //assume rec index occurs at time of spawning so never have available in current year
                                                    {
                                                     TAC(j,r,x,y)=rec_index_prop_BM(j,r,y-1)*input_u(j,r,x)*biomass_population(j,y)/nfleets(j); //partition regional quota evenly by fleets in region
                                                    }
                                                   }
                                                  if(calc_TAC_from_uMSY==2)
                                                   {
                                                   if(y==1)
                                                    {
                                                     TAC(j,r,x,y)=input_u(j,r,x)*biomass_AM(j,r,y)/(nregions(j)*nfleets(j)); //partition evenly by total fleets in area
                                                    }
                                                   if(y>1) //assume rec index occurs at time of spawning so never have available in current year
                                                    {
                                                     TAC(j,r,x,y)=rec_index_prop_BM(j,r,y-1)*input_u(j,r,x)*biomass_AM(j,r,y)/nfleets(j); //partition regional quota evenly by fleets in region
                                                    }
                                                   }
                                                  }
                                                 if(parse_TAC_source==1)
                                                  {
                                                  if(calc_TAC_from_uMSY==0)
                                                   {
                                                   if(y==1)
                                                    {
                                                     TAC(j,r,x,y)=input_TAC(j,r,x)/(nregions(j)*nfleets(j)); //partition evenly by total fleets in area
                                                    }
                                                   if(y>1) //assume rec index occurs at time of spawning so never have available in current year
                                                    {
                                                     TAC(j,r,x,y)=rec_index_prop_AM(j,r,y-1)*input_TAC(j,r,x)/nfleets(j); //partition regional quota evenly by fleets in region
                                                    }
                                                   }
                                                  if(calc_TAC_from_uMSY==1)
                                                   {
                                                   if(y==1)
                                                    {
                                                     TAC(j,r,x,y)=input_u(j,r,x)*biomass_population(j,y)/(nregions(j)*nfleets(j)); //partition evenly by total fleets in area
                                                    }
                                                   if(y>1) //assume rec index occurs at time of spawning so never have available in current year
                                                    {
                                                     TAC(j,r,x,y)=rec_index_prop_AM(j,r,y-1)*input_u(j,r,x)*biomass_population(j,y)/nfleets(j); //partition regional quota evenly by fleets in region
                                                    }
                                                   }
                                                  if(calc_TAC_from_uMSY==2)
                                                   {
                                                   if(y==1)
                                                    {
                                                     TAC(j,r,x,y)=input_u(j,r,x)*biomass_AM(j,r,y)/(nregions(j)*nfleets(j)); //partition evenly by total fleets in area
                                                    }
                                                   if(y>1) //assume rec index occurs at time of spawning so never have available in current year
                                                    {
                                                     TAC(j,r,x,y)=rec_index_prop_AM(j,r,y-1)*input_u(j,r,x)*biomass_AM(j,r,y)/nfleets(j); //partition regional quota evenly by fleets in region
                                                    }
                                                   }
                                                  }
                                                 if(parse_TAC_source==2)
                                                  {
                                                  if(calc_TAC_from_uMSY==0)
                                                   {
                                                   if(TAC_survey_parse_timelag_switch==1) //use timelag
                                                    {
                                                       if(y<=TAC_survey_parse_timelag) //apportion TAC equally among fleets if y<timelag
                                                        {                                                     
                                                         TAC(j,r,x,y)=input_TAC(j,r,x)/(nregions(j)*nfleets(j));
                                                        }
                                                       if(y>TAC_survey_parse_timelag)
                                                        {                                                     
                                                         TAC(j,r,x,y)=apport_region_survey_biomass(j,r,(y-TAC_survey_parse_timelag))*input_TAC(j,r,x)/nfleets(j);
                                                        }
                                                     }
                                                  if(TAC_survey_parse_timelag_switch==0) //no timelag
                                                    {
                                                     if(tsurvey(j,r)==0)
                                                      {
                                                       TAC(j,r,x,y)=apport_region_survey_biomass(j,r,y)*input_TAC(j,r,x)/nfleets(j);
                                                      }
                                                     if(tsurvey(j,r)>0)
                                                      {
                                                       if(y==1) //first year apportion TAC equally among fleets
                                                        {                                                     
                                                         TAC(j,r,x,y)=input_TAC(j,r,x)/(nregions(j)*nfleets(j));
                                                        }
                                                       if(y>1)
                                                        {                                                     
                                                         TAC(j,r,x,y)=apport_region_survey_biomass(j,r,y-1)*input_TAC(j,r,x)/nfleets(j);
                                                        }
                                                       }
                                                     }
                                                    }
                                                  if(calc_TAC_from_uMSY==1)
                                                   {
                                                   if(TAC_survey_parse_timelag_switch==1) //use timelag
                                                    {
                                                       if(y<=TAC_survey_parse_timelag)
                                                        {                                                     
                                                         TAC(j,r,x,y)=input_u(j,r,x)*biomass_population(j,y)/(nregions(j)*nfleets(j));
                                                        }
                                                       if(y>TAC_survey_parse_timelag)
                                                        {                                                     
                                                         TAC(j,r,x,y)=apport_region_survey_biomass(j,r,(y-TAC_survey_parse_timelag))*input_u(j,r,x)*biomass_population(j,y)/nfleets(j);
                                                        }
                                                     }
                                                  if(TAC_survey_parse_timelag_switch==0) //no timelag
                                                    {
                                                     if(tsurvey(j,r)==0)
                                                      {
                                                       TAC(j,r,x,y)=apport_region_survey_biomass(j,r,y)*input_u(j,r,x)*biomass_population(j,y)/nfleets(j);
                                                      }
                                                     if(tsurvey(j,r)>0)
                                                      {
                                                       if(y==1) //first year apportion TAC equally among fleets
                                                        {                                                     
                                                         TAC(j,r,x,y)=input_u(j,r,x)*biomass_population(j,y)/(nregions(j)*nfleets(j));
                                                        }
                                                       if(y>1)
                                                        {                                                     
                                                         TAC(j,r,x,y)=apport_region_survey_biomass(j,r,y-1)*input_u(j,r,x)*biomass_population(j,y)/nfleets(j);
                                                        }
                                                       }
                                                     }
                                                    }
                                                  if(calc_TAC_from_uMSY==2)
                                                   {
                                                   if(TAC_survey_parse_timelag_switch==1) //use timelag
                                                    {
                                                       if(y<=TAC_survey_parse_timelag)
                                                        {                                                     
                                                         TAC(j,r,x,y)=input_u(j,r,x)*biomass_AM(j,r,y)/(nregions(j)*nfleets(j));
                                                        }
                                                       if(y>TAC_survey_parse_timelag)
                                                        {                                                     
                                                         TAC(j,r,x,y)=apport_region_survey_biomass(j,r,(y-TAC_survey_parse_timelag))*input_u(j,r,x)*biomass_AM(j,r,y)/nfleets(j);
                                                        }
                                                     }
                                                  if(TAC_survey_parse_timelag_switch==0) //no timelag
                                                    {
                                                     if(tsurvey(j,r)==0)
                                                      {
                                                       TAC(j,r,x,y)=apport_region_survey_biomass(j,r,y)*input_u(j,r,x)*biomass_AM(j,r,y)/nfleets(j);
                                                      }
                                                     if(tsurvey(j,r)>0)
                                                      {
                                                       if(y==1) //first year apportion TAC equally among fleets
                                                        {                                                     
                                                         TAC(j,r,x,y)=input_u(j,r,x)*biomass_AM(j,r,y)/(nregions(j)*nfleets(j));
                                                        }
                                                       if(y>1)
                                                        {                                                     
                                                         TAC(j,r,x,y)=apport_region_survey_biomass(j,r,y-1)*input_u(j,r,x)*biomass_AM(j,r,y)/nfleets(j);
                                                        }
                                                       }
                                                     }
                                                    }
                                                   }
                                                 if(parse_TAC_source==3)
                                                  {
                                                  if(calc_TAC_from_uMSY==0)
                                                   {
                                                    TAC(j,r,x,y)=input_TAC(j,r,x)/(nregions(j)*nfleets(j));
                                                   }
                                                  if(calc_TAC_from_uMSY==1)
                                                   {
                                                    TAC(j,r,x,y)=input_u(j,r,x)*biomass_population(j,y)/(nregions(j)*nfleets(j));
                                                   }
                                                  if(calc_TAC_from_uMSY==2)
                                                   {
                                                    TAC(j,r,x,y)=input_u(j,r,x)*biomass_AM(j,r,y)/(nregions(j)*nfleets(j));
                                                   }
                                                  }
                                                 }
                                     if(TAC(j,r,x,y)==0) //iterationp have trouble finding F=0 when target=0; but they work great for >0 values.  This prevents those issues
                                       {
                                        Fnew=0;
                                       }
                                     if(TAC(j,r,x,y)>0) //iterationp have trouble finding F=0 when target=0; but they work great for >0 values.  This prevents those issues
                                      {
                                        Fnew=Fnew_start;
                                        for(int i=1;i<=NR_iterationp;i++)  //newton-raphson iterationp
                                         {
                                          delt=Fnew*NR_dev;  // NR_dev~0.001
                                           for(int s=1;s<=nages;s++)
                                             {
                                              if(s==1)
                                               {
                                                 fofFvect(s)=((Fnew*selectivity(j,r,y,s,x))/(Fnew*selectivity(j,r,y,s,x)+M(j,r,y,s)))*biomass_AM_overlap_age_region_all_natal(j,r,y,s)*(1-mfexp(-1*(Fnew*selectivity(j,r,y,s,x)+M(j,r,y,s))*(1-tspawn(j))));
                                                 fprimeFhigh(s)=(((Fnew+delt)*selectivity(j,r,y,s,x))/((Fnew+delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))*biomass_AM_overlap_age_region_all_natal(j,r,y,s)*(1-mfexp(-1*((Fnew+delt)*selectivity(j,r,y,s,x)+M(j,r,y,s))*(1-tspawn(j))));
                                                 fprimeFlow(s)=(((Fnew-delt)*selectivity(j,r,y,s,x))/((Fnew-delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))*biomass_AM_overlap_age_region_all_natal(j,r,y,s)*(1-mfexp(-1*((Fnew-delt)*selectivity(j,r,y,s,x)+M(j,r,y,s))*(1-tspawn(j))));                                              
                                               }
                                              if(s>1)
                                               {
                                                fofFvect(s)=((Fnew*selectivity(j,r,y,s,x))/(Fnew*selectivity(j,r,y,s,x)+M(j,r,y,s)))*biomass_AM_overlap_age_region_all_natal(j,r,y,s)*(1-mfexp(-1*(Fnew*selectivity(j,r,y,s,x)+M(j,r,y,s))));
                                                fprimeFhigh(s)=(((Fnew+delt)*selectivity(j,r,y,s,x))/((Fnew+delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))*biomass_AM_overlap_age_region_all_natal(j,r,y,s)*(1-mfexp(-1*((Fnew+delt)*selectivity(j,r,y,s,x)+M(j,r,y,s))));
                                                fprimeFlow(s)=(((Fnew-delt)*selectivity(j,r,y,s,x))/((Fnew-delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))*biomass_AM_overlap_age_region_all_natal(j,r,y,s)*(1-mfexp(-1*((Fnew-delt)*selectivity(j,r,y,s,x)+M(j,r,y,s))));
                                               }
                                             }
                                              fofF=sum(fofFvect)-TAC(j,r,x,y);
                                              fprimeF=(sum(fprimeFhigh)-sum(fprimeFlow))/(2.0*delt);
                                              Fnew=Fnew-(fofF/fprimeF);                                           
                                          if(Fnew<0) Fnew=0.5*(Fnew+(fofF/fprimeF));
                                          if(Fnew>max_Fnew) Fnew=max_Fnew;  //At low N, Fnew would sometimes be really high and I'd get an error message.  This prevents those errors.
                                         }
                                         } 
                                       }
                                 if(natal_homing_switch==0)
                                   {
                                               if(parse_TAC==0) //use input TAC
                                                {
                                                  if(calc_TAC_from_uMSY==0)
                                                   {
                                                    TAC(j,r,x,y)=input_TAC(j,r,x);
                                                   }
                                                   if(calc_TAC_from_uMSY==1)
                                                   {
                                                    TAC(j,r,x,y)=input_u(j,r,x)*biomass_population(j,y);
                                                   }
                                                   if(calc_TAC_from_uMSY==2)
                                                   {
                                                    TAC(j,r,x,y)=input_u(j,r,x)*biomass_AM(j,r,y);
                                                   }
                                                }
                                             if(parse_TAC==1) //use observed data to parse input_TAC by region // if multiple fleets then evenly distribute across fleets
                                                {
                                                 if(parse_TAC_source==0)
                                                  {
                                                  if(calc_TAC_from_uMSY==0)
                                                   {
                                                   if(y==1)
                                                    {
                                                     TAC(j,r,x,y)=input_TAC(j,r,x)/(nregions(j)*nfleets(j)); //partition evenly by total fleets in area
                                                    }
                                                   if(y>1) //assume rec index occurs at time of spawning so never have available in current year
                                                    {
                                                     TAC(j,r,x,y)=rec_index_prop_BM(j,r,y-1)*input_TAC(j,r,x)/nfleets(j); //partition regional quota evenly by fleets in region
                                                    }
                                                   }
                                                  if(calc_TAC_from_uMSY==1)
                                                   {
                                                   if(y==1)
                                                    {
                                                     TAC(j,r,x,y)=input_u(j,r,x)*biomass_population(j,y)/(nregions(j)*nfleets(j)); //partition evenly by total fleets in area
                                                    }
                                                   if(y>1) //assume rec index occurs at time of spawning so never have available in current year
                                                    {
                                                     TAC(j,r,x,y)=rec_index_prop_BM(j,r,y-1)*input_u(j,r,x)*biomass_population(j,y)/nfleets(j); //partition regional quota evenly by fleets in region
                                                    }
                                                   }
                                                  if(calc_TAC_from_uMSY==2)
                                                   {
                                                   if(y==1)
                                                    {
                                                     TAC(j,r,x,y)=input_u(j,r,x)*biomass_AM(j,r,y)/(nregions(j)*nfleets(j)); //partition evenly by total fleets in area
                                                    }
                                                   if(y>1) //assume rec index occurs at time of spawning so never have available in current year
                                                    {
                                                     TAC(j,r,x,y)=rec_index_prop_BM(j,r,y-1)*input_u(j,r,x)*biomass_AM(j,r,y)/nfleets(j); //partition regional quota evenly by fleets in region
                                                    }
                                                   }
                                                  }
                                                 if(parse_TAC_source==1)
                                                  {
                                                  if(calc_TAC_from_uMSY==0)
                                                   {
                                                   if(y==1)
                                                    {
                                                     TAC(j,r,x,y)=input_TAC(j,r,x)/(nregions(j)*nfleets(j)); //partition evenly by total fleets in area
                                                    }
                                                   if(y>1) //assume rec index occurs at time of spawning so never have available in current year
                                                    {
                                                     TAC(j,r,x,y)=rec_index_prop_AM(j,r,y-1)*input_TAC(j,r,x)/nfleets(j); //partition regional quota evenly by fleets in region
                                                    }
                                                   }
                                                  if(calc_TAC_from_uMSY==1)
                                                   {
                                                   if(y==1)
                                                    {
                                                     TAC(j,r,x,y)=input_u(j,r,x)*biomass_population(j,y)/(nregions(j)*nfleets(j)); //partition evenly by total fleets in area
                                                    }
                                                   if(y>1) //assume rec index occurs at time of spawning so never have available in current year
                                                    {
                                                     TAC(j,r,x,y)=rec_index_prop_AM(j,r,y-1)*input_u(j,r,x)*biomass_population(j,y)/nfleets(j); //partition regional quota evenly by fleets in region
                                                    }
                                                   }
                                                  if(calc_TAC_from_uMSY==2)
                                                   {
                                                   if(y==1)
                                                    {
                                                     TAC(j,r,x,y)=input_u(j,r,x)*biomass_AM(j,r,y)/(nregions(j)*nfleets(j)); //partition evenly by total fleets in area
                                                    }
                                                   if(y>1) //assume rec index occurs at time of spawning so never have available in current year
                                                    {
                                                     TAC(j,r,x,y)=rec_index_prop_AM(j,r,y-1)*input_u(j,r,x)*biomass_AM(j,r,y)/nfleets(j); //partition regional quota evenly by fleets in region
                                                    }
                                                   }
                                                  }
                                                 if(parse_TAC_source==2)
                                                  {
                                                  if(calc_TAC_from_uMSY==0)
                                                   {
                                                   if(TAC_survey_parse_timelag_switch==1) //use timelag
                                                    {
                                                       if(y<=TAC_survey_parse_timelag) //apportion TAC equally among fleets if y<timelag
                                                        {                                                     
                                                         TAC(j,r,x,y)=input_TAC(j,r,x)/(nregions(j)*nfleets(j));
                                                        }
                                                       if(y>TAC_survey_parse_timelag)
                                                        {                                                     
                                                         TAC(j,r,x,y)=apport_region_survey_biomass(j,r,(y-TAC_survey_parse_timelag))*input_TAC(j,r,x)/nfleets(j);
                                                        }
                                                     }
                                                  if(TAC_survey_parse_timelag_switch==0) //no timelag
                                                    {
                                                     if(tsurvey(j,r)==0)
                                                      {
                                                       TAC(j,r,x,y)=apport_region_survey_biomass(j,r,y)*input_TAC(j,r,x)/nfleets(j);
                                                      }
                                                     if(tsurvey(j,r)>0)
                                                      {
                                                       if(y==1) //first year apportion TAC equally among fleets
                                                        {                                                     
                                                         TAC(j,r,x,y)=input_TAC(j,r,x)/(nregions(j)*nfleets(j));
                                                        }
                                                       if(y>1)
                                                        {                                                     
                                                         TAC(j,r,x,y)=apport_region_survey_biomass(j,r,y-1)*input_TAC(j,r,x)/nfleets(j);
                                                        }
                                                       }
                                                     }
                                                    }
                                                  if(calc_TAC_from_uMSY==1)
                                                   {
                                                   if(TAC_survey_parse_timelag_switch==1) //use timelag
                                                    {
                                                       if(y<=TAC_survey_parse_timelag)
                                                        {                                                     
                                                         TAC(j,r,x,y)=input_u(j,r,x)*biomass_population(j,y)/(nregions(j)*nfleets(j));
                                                        }
                                                       if(y>TAC_survey_parse_timelag)
                                                        {                                                     
                                                         TAC(j,r,x,y)=apport_region_survey_biomass(j,r,(y-TAC_survey_parse_timelag))*input_u(j,r,x)*biomass_population(j,y)/nfleets(j);
                                                        }
                                                     }
                                                  if(TAC_survey_parse_timelag_switch==0) //no timelag
                                                    {
                                                     if(tsurvey(j,r)==0)
                                                      {
                                                       TAC(j,r,x,y)=apport_region_survey_biomass(j,r,y)*input_u(j,r,x)*biomass_population(j,y)/nfleets(j);
                                                      }
                                                     if(tsurvey(j,r)>0)
                                                      {
                                                       if(y==1) //first year apportion TAC equally among fleets
                                                        {                                                     
                                                         TAC(j,r,x,y)=input_u(j,r,x)*biomass_population(j,y)/(nregions(j)*nfleets(j));
                                                        }
                                                       if(y>1)
                                                        {                                                     
                                                         TAC(j,r,x,y)=apport_region_survey_biomass(j,r,y-1)*input_u(j,r,x)*biomass_population(j,y)/nfleets(j);
                                                        }
                                                       }
                                                     }
                                                    }
                                                  if(calc_TAC_from_uMSY==2)
                                                   {
                                                   if(TAC_survey_parse_timelag_switch==1) //use timelag
                                                    {
                                                       if(y<=TAC_survey_parse_timelag)
                                                        {                                                     
                                                         TAC(j,r,x,y)=input_u(j,r,x)*biomass_AM(j,r,y)/(nregions(j)*nfleets(j));
                                                        }
                                                       if(y>TAC_survey_parse_timelag)
                                                        {                                                     
                                                         TAC(j,r,x,y)=apport_region_survey_biomass(j,r,(y-TAC_survey_parse_timelag))*input_u(j,r,x)*biomass_AM(j,r,y)/nfleets(j);
                                                        }
                                                     }
                                                  if(TAC_survey_parse_timelag_switch==0) //no timelag
                                                    {
                                                     if(tsurvey(j,r)==0)
                                                      {
                                                       TAC(j,r,x,y)=apport_region_survey_biomass(j,r,y)*input_u(j,r,x)*biomass_AM(j,r,y)/nfleets(j);
                                                      }
                                                     if(tsurvey(j,r)>0)
                                                      {
                                                       if(y==1) //first year apportion TAC equally among fleets
                                                        {                                                     
                                                         TAC(j,r,x,y)=input_u(j,r,x)*biomass_AM(j,r,y)/(nregions(j)*nfleets(j));
                                                        }
                                                       if(y>1)
                                                        {                                                     
                                                         TAC(j,r,x,y)=apport_region_survey_biomass(j,r,y-1)*input_u(j,r,x)*biomass_AM(j,r,y)/nfleets(j);
                                                        }
                                                       }
                                                     }
                                                    }
                                                   }
                                                 if(parse_TAC_source==3)
                                                  {
                                                  if(calc_TAC_from_uMSY==0)
                                                   {
                                                    TAC(j,r,x,y)=input_TAC(j,r,x)/(nregions(j)*nfleets(j));
                                                   }
                                                  if(calc_TAC_from_uMSY==1)
                                                   {
                                                    TAC(j,r,x,y)=input_u(j,r,x)*biomass_population(j,y)/(nregions(j)*nfleets(j));
                                                   }
                                                  if(calc_TAC_from_uMSY==2)
                                                   {
                                                    TAC(j,r,x,y)=input_u(j,r,x)*biomass_AM(j,r,y)/(nregions(j)*nfleets(j));
                                                   }
                                                  }
                                                 }
                                     if(TAC(j,r,x,y)==0) //iterationp have trouble finding F=0 when target=0; but they work great for >0 values.  This prevents those issues
                                       {
                                        Fnew=0;
                                       }
                                     if(TAC(j,r,x,y)>0) //iterationp have trouble finding F=0 when target=0; but they work great for >0 values.  This prevents those issues
                                      {
                                        Fnew=Fnew_start;
                                        for(int i=1;i<=NR_iterationp;i++)  //newton-raphson iterationp
                                         {
                                          delt=Fnew*NR_dev;  // NR_dev~0.001
                                           for(int s=1;s<=nages;s++)
                                            {
                                              if(s==1)
                                              {
                                               fofFvect(s)=weight_catch(j,r,y,s)*((Fnew*selectivity(j,r,y,s,x))/(Fnew*selectivity(j,r,y,s,x)+M(j,r,y,s)))*abundance_at_age_AM(j,r,y,s)*(1-mfexp(-1*(Fnew*selectivity(j,r,y,s,x)+M(j,r,y,s))*(1-tspawn(j))));
                                               fprimeFhigh(s)=weight_catch(j,r,y,s)*(((Fnew+delt)*selectivity(j,r,y,s,x))/((Fnew+delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))*abundance_at_age_AM(j,r,y,s)*(1-mfexp(-1*((Fnew+delt)*selectivity(j,r,y,s,x)+M(j,r,y,s))*(1-tspawn(j))));
                                               fprimeFlow(s)=weight_catch(j,r,y,s)*(((Fnew-delt)*selectivity(j,r,y,s,x))/((Fnew-delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))*abundance_at_age_AM(j,r,y,s)*(1-mfexp(-1*((Fnew-delt)*selectivity(j,r,y,s,x)+M(j,r,y,s))*(1-tspawn(j))));                                              
                                              }
                                              if(s>1)
                                              {
                                              fofFvect(s)=weight_catch(j,r,y,s)*((Fnew*selectivity(j,r,y,s,x))/(Fnew*selectivity(j,r,y,s,x)+M(j,r,y,s)))*abundance_at_age_AM(j,r,y,s)*(1-mfexp(-1*(Fnew*selectivity(j,r,y,s,x)+M(j,r,y,s))));
                                              fprimeFhigh(s)=weight_catch(j,r,y,s)*(((Fnew+delt)*selectivity(j,r,y,s,x))/((Fnew+delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))*abundance_at_age_AM(j,r,y,s)*(1-mfexp(-1*((Fnew+delt)*selectivity(j,r,y,s,x)+M(j,r,y,s))));
                                              fprimeFlow(s)=weight_catch(j,r,y,s)*(((Fnew-delt)*selectivity(j,r,y,s,x))/((Fnew-delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))*abundance_at_age_AM(j,r,y,s)*(1-mfexp(-1*((Fnew-delt)*selectivity(j,r,y,s,x)+M(j,r,y,s))));
                                              }
                                             }
                                            fofF=sum(fofFvect)-TAC(j,r,x,y);
                                            fprimeF=(sum(fprimeFhigh)-sum(fprimeFlow))/(2.0*delt);
                                            Fnew=Fnew-(fofF/fprimeF);
                                          if(Fnew<0) Fnew=0.5*(Fnew+(fofF/fprimeF));
                                          if(Fnew>max_Fnew) Fnew=max_Fnew;  //At low N, Fnew would sometimes be really high and I'd get an error message.  This prevents those errors.
                                         }
                                       } 
                                      }
                                     }

                             if(model_type_switch==2)
                                {
                                 if(natal_homing_switch>0)
                                   {
                                               if(parse_TAC==0) //use observed data to parse input_TAC by region // if multiple fleets then evenly distribute across fleets
                                                {
                                                 u(j,r,x)=input_u(j,r,x);
                                                }
                                               if(parse_TAC==1) //use observed data to parse input_TAC by region // if multiple fleets then evenly distribute across fleets
                                                {
                                                 if(parse_TAC_source==0)
                                                  {
                                                   if(y==1)
                                                    {
                                                     u(j,r,x)=input_u(j,r,x)/(nregions(j)*nfleets(j));
                                                    }
                                                   if(y>1)
                                                    {
                                                     u(j,r,x)=rec_index_prop_BM(j,r,y-1)*input_u(j,r,x)/nfleets(j);
                                                    }
                                                  }
                                                 if(parse_TAC_source==1)
                                                  {
                                                   if(y==1)
                                                    {
                                                     u(j,r,x)=input_u(j,r,x)/(nregions(j)*nfleets(j));
                                                    }
                                                   if(y>1)
                                                    {
                                                     u(j,r,x)=rec_index_prop_AM(j,r,y-1)*input_u(j,r,x)/nfleets(j);
                                                    }
                                                   }
                                                 if(parse_TAC_source==2)
                                                  {
                                                   if(TAC_survey_parse_timelag_switch==1) //use timelag
                                                    {
                                                       if(y<=TAC_survey_parse_timelag) //first year apportion TAC equally among fleets
                                                        {                                                     
                                                         u(j,r,x)=input_u(j,r,x)/(nregions(j)*nfleets(j));
                                                        }
                                                       if(y>TAC_survey_parse_timelag)
                                                        {                                                     
                                                         u(j,r,x)=apport_region_survey_biomass(j,r,(y-TAC_survey_parse_timelag))*input_u(j,r,x)/nfleets(j);
                                                        }
                                                     }
                                                  if(TAC_survey_parse_timelag_switch==0) //no timelag
                                                    {
                                                     if(tsurvey(j,r)==0)
                                                      {
                                                       u(j,r,x)=apport_region_survey_biomass(j,r,y)*input_u(j,r,x)/nfleets(j);
                                                      }
                                                     if(tsurvey(j,r)>0)
                                                      {
                                                       if(y==1) //first year apportion TAC equally among fleets
                                                        {                                                     
                                                         u(j,r,x)=input_u(j,r,x)/(nregions(j)*nfleets(j));
                                                        }
                                                       if(y>1)
                                                        {                                                     
                                                         u(j,r,x)=apport_region_survey_biomass(j,r,y-1)*input_u(j,r,x)/nfleets(j);
                                                        }
                                                       }
                                                     }
                                                    }
                                                 if(parse_TAC_source==3)
                                                  {
                                                   u(j,r,x)=input_u(j,r,x)/(nregions(j)*nfleets(j));
                                                  }
                                                 }
                                     if(u(j,r,x)==0) //iterationp have trouble finding F=0 when target=0; but they work great for >0 values.  This prevents those issues
                                       {
                                        Fnew=0;
                                       }
                                     if(u(j,r,x)>0) //iterationp have trouble finding F=0 when target=0; but they work great for >0 values.  This prevents those issues
                                      {
                                        Fnew=Fnew_start;
                                        for(int i=1;i<=NR_iterationp;i++)  //newton-raphson iterationp
                                         {
                                          delt=Fnew*NR_dev;  // NR_dev~0.001
                                           for(int s=1;s<=nages;s++)
                                             {
                                              if(s==1)
                                               {  
                                                 fofFvect(s)=(((Fnew*selectivity(j,r,y,s,x))/(Fnew*selectivity(j,r,y,s,x)+M(j,r,y,s)))*biomass_AM_overlap_age_region_all_natal(j,r,y,s)*(1-mfexp(-1*(Fnew*selectivity(j,r,y,s,x)+M(j,r,y,s))*(1-tspawn(j)))))/biomass_AM_overlap_region_all_natal(j,r,y);
                                                 fprimeFhigh(s)=((((Fnew+delt)*selectivity(j,r,y,s,x))/((Fnew+delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))*biomass_AM_overlap_age_region_all_natal(j,r,y,s)*(1-mfexp(-1*((Fnew+delt)*selectivity(j,r,y,s,x)+M(j,r,y,s))*(1-tspawn(j)))))/biomass_AM_overlap_region_all_natal(j,r,y);
                                                 fprimeFlow(s)=((((Fnew-delt)*selectivity(j,r,y,s,x))/((Fnew-delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))*biomass_AM_overlap_age_region_all_natal(j,r,y,s)*(1-mfexp(-1*((Fnew-delt)*selectivity(j,r,y,s,x)+M(j,r,y,s))*(1-tspawn(j)))))/biomass_AM_overlap_region_all_natal(j,r,y);                                              
                                               }
                                              if(s>1)
                                               {
                                                fofFvect(s)=(((Fnew*selectivity(j,r,y,s,x))/(Fnew*selectivity(j,r,y,s,x)+M(j,r,y,s)))*biomass_AM_overlap_age_region_all_natal(j,r,y,s)*(1-mfexp(-1*(Fnew*selectivity(j,r,y,s,x)+M(j,r,y,s)))))/biomass_AM_overlap_region_all_natal(j,r,y);
                                                fprimeFhigh(s)=((((Fnew+delt)*selectivity(j,r,y,s,x))/((Fnew+delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))*biomass_AM_overlap_age_region_all_natal(j,r,y,s)*(1-mfexp(-1*((Fnew+delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))))/biomass_AM_overlap_region_all_natal(j,r,y);
                                                fprimeFlow(s)=((((Fnew-delt)*selectivity(j,r,y,s,x))/((Fnew-delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))*biomass_AM_overlap_age_region_all_natal(j,r,y,s)*(1-mfexp(-1*((Fnew-delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))))/biomass_AM_overlap_region_all_natal(j,r,y);
                                               }
                                             } 
                                            fofF=sum(fofFvect)-u(j,r,x);
                                            fprimeF=(sum(fprimeFhigh)-sum(fprimeFlow))/(2.0*delt);
                                            Fnew=Fnew-(fofF/fprimeF);
                                          if(Fnew<0) Fnew=0.5*(Fnew+(fofF/fprimeF));
                                          if(Fnew>max_Fnew) Fnew=max_Fnew;  //At low N, Fnew would sometimes be really high and I'd get an error message.  This prevents those errors.
                                         }
                                         } 
                                       }
                                 if(natal_homing_switch==0)
                                   {
                                               if(parse_TAC==0) //use observed data to parse input_TAC by region // if multiple fleets then evenly distribute across fleets
                                                {
                                                 u(j,r,x)=input_u(j,r,x);
                                                }
                                               if(parse_TAC==1) //use observed data to parse input_TAC by region // if multiple fleets then evenly distribute across fleets
                                                {
                                                 if(parse_TAC_source==0)
                                                  {
                                                   if(y==1)
                                                    {
                                                     u(j,r,x)=input_u(j,r,x)/(nregions(j)*nfleets(j));
                                                    }
                                                   if(y>1)
                                                    {
                                                     u(j,r,x)=rec_index_prop_BM(j,r,y-1)*input_u(j,r,x)/nfleets(j);
                                                    }
                                                  }
                                                 if(parse_TAC_source==1)
                                                  {
                                                   if(y==1)
                                                    {
                                                     u(j,r,x)=input_u(j,r,x)/(nregions(j)*nfleets(j));
                                                    }
                                                   if(y>1)
                                                    {
                                                     u(j,r,x)=rec_index_prop_AM(j,r,y-1)*input_u(j,r,x)/nfleets(j);
                                                    }
                                                   }
                                                 if(parse_TAC_source==2)
                                                  {
                                                   if(TAC_survey_parse_timelag_switch==1) //use timelag
                                                    {
                                                       if(y<=TAC_survey_parse_timelag) //first year apportion TAC equally among fleets
                                                        {                                                     
                                                         u(j,r,x)=input_u(j,r,x)/(nregions(j)*nfleets(j));
                                                        }
                                                       if(y>TAC_survey_parse_timelag)
                                                        {                                                     
                                                         u(j,r,x)=apport_region_survey_biomass(j,r,(y-TAC_survey_parse_timelag))*input_u(j,r,x)/nfleets(j);
                                                        }
                                                     }
                                                  if(TAC_survey_parse_timelag_switch==0) //no timelag
                                                    {
                                                     if(tsurvey(j,r)==0)
                                                      {
                                                       u(j,r,x)=apport_region_survey_biomass(j,r,y)*input_u(j,r,x)/nfleets(j);
                                                      }
                                                     if(tsurvey(j,r)>0)
                                                      {
                                                       if(y==1) //first year apportion TAC equally among fleets
                                                        {                                                     
                                                         u(j,r,x)=input_u(j,r,x)/(nregions(j)*nfleets(j));
                                                        }
                                                       if(y>1)
                                                        {                                                     
                                                         u(j,r,x)=apport_region_survey_biomass(j,r,y-1)*input_u(j,r,x)/nfleets(j);
                                                        }
                                                       }
                                                     }
                                                    }
                                                 if(parse_TAC_source==3)
                                                  {
                                                   u(j,r,x)=input_u(j,r,x)/(nregions(j)*nfleets(j));
                                                  }
                                                 }
                                     if(u(j,r,x)==0) //iterationp have trouble finding F=0 when target=0; but they work great for >0 values.  This prevents those issues
                                       {
                                        Fnew=0;
                                       }
                                     if(u(j,r,x)>0) //iterationp have trouble finding F=0 when target=0; but they work great for >0 values.  This prevents those issues
                                      {
                                        Fnew=Fnew_start;
                                        for(int i=1;i<=NR_iterationp;i++)  //newton-raphson iterationp
                                         {
                                          delt=Fnew*NR_dev;  // NR_dev~0.001
                                           for(int s=1;s<=nages;s++)
                                            {
                                              if(s==1)
                                              {
                                               fofFvect(s)=(weight_catch(j,r,y,s)*((Fnew*selectivity(j,r,y,s,x))/(Fnew*selectivity(j,r,y,s,x)+M(j,r,y,s)))*abundance_at_age_AM(j,r,y,s)*(1-mfexp(-1*(Fnew*selectivity(j,r,y,s,x)+M(j,r,y,s))*(1-tspawn(j)))))/biomass_AM(j,r,y);
                                               fprimeFhigh(s)=(weight_catch(j,r,y,s)*(((Fnew+delt)*selectivity(j,r,y,s,x))/((Fnew+delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))*abundance_at_age_AM(j,r,y,s)*(1-mfexp(-1*((Fnew+delt)*selectivity(j,r,y,s,x)+M(j,r,y,s))*(1-tspawn(j)))))/biomass_AM(j,r,y);
                                               fprimeFlow(s)=(weight_catch(j,r,y,s)*(((Fnew-delt)*selectivity(j,r,y,s,x))/((Fnew-delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))*abundance_at_age_AM(j,r,y,s)*(1-mfexp(-1*((Fnew-delt)*selectivity(j,r,y,s,x)+M(j,r,y,s))*(1-tspawn(j)))))/biomass_AM(j,r,y);                                              
                                              }
                                              if(s>1)
                                              {
                                              fofFvect(s)=(weight_catch(j,r,y,s)*((Fnew*selectivity(j,r,y,s,x))/(Fnew*selectivity(j,r,y,s,x)+M(j,r,y,s)))*abundance_at_age_AM(j,r,y,s)*(1-mfexp(-1*(Fnew*selectivity(j,r,y,s,x)+M(j,r,y,s)))))/biomass_AM(j,r,y);
                                              fprimeFhigh(s)=(weight_catch(j,r,y,s)*(((Fnew+delt)*selectivity(j,r,y,s,x))/((Fnew+delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))*abundance_at_age_AM(j,r,y,s)*(1-mfexp(-1*((Fnew+delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))))/biomass_AM(j,r,y);
                                              fprimeFlow(s)=(weight_catch(j,r,y,s)*(((Fnew-delt)*selectivity(j,r,y,s,x))/((Fnew-delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))*abundance_at_age_AM(j,r,y,s)*(1-mfexp(-1*((Fnew-delt)*selectivity(j,r,y,s,x)+M(j,r,y,s)))))/biomass_AM(j,r,y);
                                              }
                                             }
                                            fofF=sum(fofFvect)-u(j,r,x);
                                            fprimeF=(sum(fprimeFhigh)-sum(fprimeFlow))/(2.0*delt);
                                            Fnew=Fnew-(fofF/fprimeF);
                                          if(Fnew<0) Fnew=0.5*(Fnew+(fofF/fprimeF));
                                          if(Fnew>max_Fnew) Fnew=max_Fnew;  //At low N, Fnew would sometimes be really high and I'd get an error message.  This prevents those errors.
                                         }
                                       } 
                                      }
                                     }
                             F_fleet(j,r,y,a,x)=Fnew*selectivity(j,r,y,a,x);                                         
                         }
                       F(j,r,y,a)=sum(F_fleet(j,r,y,a)); 
                      }                     
                     }
                    }
                   }
                  }

  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
   //a==1 natal homing
 ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
       for (int a=1;a<=nages;a++)
         {
           for (int p=1;p<=npops;p++)
            {
             for (int j=1;j<=npops;j++)
              {
               for (int r=1;r<=nregions(j);r++)
                {
                 for (int z=1;z<=nfleets(j);z++)
                  {
          if(a==1)
            {

                abundance_spawn_overlap(p,j,r,y,a)=abundance_at_age_AM_overlap_region(p,j,y,a,r)*mfexp(-(M(j,r,y,a)+F(j,r,y,a))*tspawn(p));
                abundance_natal_temp_overlap(p,y,a,j)=abundance_at_age_AM_overlap_population(p,j,y,a);
                abundance_natal_overlap(p,y,a)=sum(abundance_natal_temp_overlap(p,y,a));
                catch_at_age_region_fleet_overlap(p,j,r,z,y,a)=abundance_at_age_AM_overlap_region(p,j,y,a,r)*(1.0-mfexp(-(F_fleet(j,r,y,a,z)+M(j,r,y,a))*(1-tspawn(p))))*(F_fleet(j,r,y,a,z)/(F_fleet(j,r,y,a,z)+M(j,r,y,a)));              
                catch_at_age_region_overlap(p,j,r,y,a)=abundance_at_age_AM_overlap_region(p,j,y,a,r)*(1.0-exp(-(F(j,r,y,a)+M(j,r,y,a))*(1-tspawn(j))))*(F(j,r,y,a)/(F(j,r,y,a)+M(j,r,y,a)));
                yield_region_fleet_temp_overlap(p,j,r,z,y,a)=weight_catch(p,r,y,a)*catch_at_age_region_fleet_overlap(p,j,r,z,y,a);
                yield_region_fleet_overlap(p,j,r,z,y)=sum(yield_region_fleet_temp_overlap(p,j,r,z,y));
                yield_region_temp_overlap(p,j,r,y,a)=weight_catch(p,r,y,a)*catch_at_age_region_overlap(p,j,r,y,a);
                yield_region_overlap(p,j,r,y)=sum(yield_region_temp_overlap(p,j,r,y));
                catch_at_age_population_temp_overlap(p,j,y,a,r)=catch_at_age_region_overlap(p,j,r,y,a);
                catch_at_age_population_overlap(p,j,y,a)=sum(catch_at_age_population_temp_overlap(p,j,y,a));
                yield_population_temp_overlap(p,j,y,a)=weight_catch(p,r,y,a)*catch_at_age_population_overlap(p,j,y,a);
                yield_population_overlap(p,j,y)=sum(yield_population_temp_overlap(p,j,y));
                catch_at_age_natal_temp_overlap(p,y,a,j)=catch_at_age_population_overlap(p,j,y,a);
                catch_at_age_natal_overlap(p,y,a)=sum(catch_at_age_natal_temp_overlap(p,y,a));
                yield_natal_temp_overlap(p,y,j)=yield_population_overlap(p,j,y);
                yield_natal_overlap(p,y)=sum(yield_natal_temp_overlap(p,y));
                harvest_rate_region_fleet_bio_overlap(p,j,r,z,y)=yield_region_fleet_overlap(p,j,r,z,y)/biomass_AM_overlap_region(p,j,r,y);
                harvest_rate_region_bio_overlap(p,j,r,y)=yield_region_overlap(p,j,r,y)/biomass_AM_overlap_region(p,j,r,y);
                harvest_rate_population_bio_overlap(p,j,y)=yield_population_overlap(p,j,y)/biomass_population_overlap(p,j,y);
                harvest_rate_natal_bio_overlap(p,y)=yield_natal_overlap(p,y)/biomass_natal_overlap(p,y);
                depletion_region_overlap(p,j,r,y)=biomass_AM_overlap_region(p,j,r,y)/biomass_AM_overlap_region(p,j,r,1);
                depletion_population_overlap(p,j,y)=biomass_population_overlap(p,j,y)/biomass_population_overlap(p,j,1);
                depletion_natal_overlap(p,y)=biomass_natal_overlap(p,y)/biomass_natal_overlap(p,1);
               
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////a==1 metapop type abundance calcs////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
 
                   abundance_spawn(j,r,y,a)=abundance_at_age_AM(j,r,y,a)*mfexp(-(M(j,r,y,a)+F(j,r,y,a))*tspawn(j));
                   catch_at_age_fleet(j,r,y,a,z)=abundance_at_age_AM(j,r,y,a)*(1.0-exp(-(F_fleet(j,r,y,a,z)+M(j,r,y,a))*(1-tspawn(j))))*(F_fleet(j,r,y,a,z))/(F(j,r,y,a)+M(j,r,y,a)); //account for time of spawning in catch (tspawn divides out in F/(F+M

                   //catchsum(j,r,y,z)=sum(catch_at_age_fleet(j,r,y,z));
                   
                   yield_fleet_temp(j,r,y,z,a)=weight_catch(j,r,y,a)*catch_at_age_fleet(j,r,y,a,z);
                   yield_fleet(j,r,y,z)=sum(yield_fleet_temp(j,r,y,z));
                   catch_at_age_region(j,r,y,a)=sum(catch_at_age_fleet(j,r,y,a));
                   yield_region_temp(j,r,y,a)=weight_catch(j,r,y,a)*catch_at_age_region(j,r,y,a);
                   yield_region(j,r,y)=sum(yield_region_temp(j,r,y));
                   catch_at_age_population_temp(j,y,a,r)=catch_at_age_region(j,r,y,a);
                   catch_at_age_population(j,y,a)=sum(catch_at_age_population_temp(j,y,a));
                   yield_population_temp(j,y,a)=weight_catch(j,r,y,a)*catch_at_age_population(j,y,a);
                   yield_population(j,y)=sum(yield_population_temp(j,y));

                abundance_population_temp(j,y,a,r)=abundance_at_age_AM(j,r,y,a);
                abundance_population(j,y,a)=sum(abundance_population_temp(j,y,a));
                abundance_total_temp(y,a,j)=abundance_population(j,y,a);
                abundance_total(y,a)=sum(abundance_total_temp(y,a));
                catch_at_age_total_temp(y,a,j)=catch_at_age_population(j,y,a);
                catch_at_age_total(y,a)=sum(catch_at_age_total_temp(y,a));
                yield_total_temp(y,j)=yield_population(j,y);
                yield_total(y)=sum(yield_total_temp(y));
                harvest_rate_region_num(j,r,y,a)=catch_at_age_region(j,r,y,a)/abundance_at_age_AM(j,r,y,a);
                harvest_rate_population_num(j,y,a)=catch_at_age_population(j,y,a)/abundance_population(j,y,a);
                harvest_rate_total_num(y,a)=catch_at_age_total(y,a)/abundance_total(y,a);
                harvest_rate_region_bio(j,r,y)=yield_region(j,r,y)/biomass_AM(j,r,y);
                harvest_rate_population_bio(j,y)=yield_population(j,y)/biomass_population(j,y);
                harvest_rate_total_bio(y)=yield_total(y)/biomass_total(y);
                depletion_region(j,r,y)=biomass_AM(j,r,y)/biomass_AM(j,r,1);
                depletion_population(j,y)=biomass_population(j,y)/biomass_population(j,1);
                depletion_total(y)=biomass_total(y)/biomass_total(1);
            } //end a==1 loop

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////a==2 overlap calcs///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
   if(a==2)
    {
                abundance_spawn_overlap(p,j,r,y,a)=abundance_at_age_AM_overlap_region(p,j,y,a,r)*mfexp(-(M(j,r,y,a)+F(j,r,y,a))*tspawn(p));
                abundance_natal_temp_overlap(p,y,a,j)=abundance_at_age_AM_overlap_population(p,j,y,a);
                abundance_natal_overlap(p,y,a)=sum(abundance_natal_temp_overlap(p,y,a));
                catch_at_age_region_fleet_overlap(p,j,r,z,y,a)=abundance_at_age_AM_overlap_region(p,j,y,a,r)*(1.0-mfexp(-(F_fleet(j,r,y,a,z)+M(j,r,y,a))))*(F_fleet(j,r,y,a,z)/(F_fleet(j,r,y,a,z)+M(j,r,y,a)));              
                yield_region_fleet_temp_overlap(p,j,r,z,y,a)=weight_catch(p,r,y,a)*catch_at_age_region_fleet_overlap(p,j,r,z,y,a);
                yield_region_fleet_overlap(p,j,r,z,y)=sum(yield_region_fleet_temp_overlap(p,j,r,z,y));
                catch_at_age_region_overlap(p,j,r,y,a)=abundance_at_age_AM_overlap_region(p,j,y,a,r)*(1.0-exp(-(F(j,r,y,a)+M(j,r,y,a))))*(F(j,r,y,a)/(F(j,r,y,a)+M(j,r,y,a)));              
                yield_region_temp_overlap(p,j,r,y,a)=weight_catch(p,r,y,a)*catch_at_age_region_overlap(p,j,r,y,a);
                yield_region_overlap(p,j,r,y)=sum(yield_region_temp_overlap(p,j,r,y));
                catch_at_age_population_temp_overlap(p,j,y,a,r)=catch_at_age_region_overlap(p,j,r,y,a);
                catch_at_age_population_overlap(p,j,y,a)=sum(catch_at_age_population_temp_overlap(p,j,y,a));
                yield_population_temp_overlap(p,j,y,a)=weight_catch(p,r,y,a)*catch_at_age_population_overlap(p,j,y,a);
                yield_population_overlap(p,j,y)=sum(yield_population_temp_overlap(p,j,y));
                catch_at_age_natal_temp_overlap(p,y,a,j)=catch_at_age_population_overlap(p,j,y,a);
                catch_at_age_natal_overlap(p,y,a)=sum(catch_at_age_natal_temp_overlap(p,y,a));
                yield_natal_temp_overlap(p,y,j)=yield_population_overlap(p,j,y);
                yield_natal_overlap(p,y)=sum(yield_natal_temp_overlap(p,y));
                harvest_rate_region_fleet_bio_overlap(p,j,r,z,y)=yield_region_fleet_overlap(p,j,r,z,y)/biomass_AM_overlap_region(p,j,r,y);
                harvest_rate_region_bio_overlap(p,j,r,y)=yield_region_overlap(p,j,r,y)/biomass_AM_overlap_region(p,j,r,y);
                harvest_rate_population_bio_overlap(p,j,y)=yield_population_overlap(p,j,y)/biomass_population_overlap(p,j,y);
                harvest_rate_natal_bio_overlap(p,y)=yield_natal_overlap(p,y)/biomass_natal_overlap(p,y);
                depletion_region_overlap(p,j,r,y)=biomass_AM_overlap_region(p,j,r,y)/biomass_AM_overlap_region(p,j,r,1);
                depletion_population_overlap(p,j,y)=biomass_population_overlap(p,j,y)/biomass_population_overlap(p,j,1);
                depletion_natal_overlap(p,y)=biomass_natal_overlap(p,y)/biomass_natal_overlap(p,1);
                            
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////a==2 metapop type abundance calcs////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                   
                  abundance_spawn(j,r,y,a)=abundance_at_age_AM(j,r,y,a)*mfexp(-(M(j,r,y,a)+F(j,r,y,a))*tspawn(j));
                  catch_at_age_fleet(j,r,y,a,z)=abundance_at_age_AM(j,r,y,a)*(1.0-exp(-(F_fleet(j,r,y,a,z)+M(j,r,y,a))))*(F_fleet(j,r,y,a,z))/(F(j,r,y,a)+M(j,r,y,a));                  
                  yield_fleet_temp(j,r,y,z,a)=weight_catch(j,r,y,a)*catch_at_age_fleet(j,r,y,a,z);
                  yield_fleet(j,r,y,z)=sum(yield_fleet_temp(j,r,y,z));
                  catch_at_age_region(j,r,y,a)=sum(catch_at_age_fleet(j,r,y,a));
                  yield_region_temp(j,r,y,a)=weight_catch(j,r,y,a)*catch_at_age_region(j,r,y,a);
                  yield_region(j,r,y)=sum(yield_region_temp(j,r,y));
                  catch_at_age_population_temp(j,y,a,r)=catch_at_age_region(j,r,y,a);
                  catch_at_age_population(j,y,a)=sum(catch_at_age_population_temp(j,y,a));
                  yield_population_temp(j,y,a)=weight_catch(j,r,y,a)*catch_at_age_population(j,y,a);
                  yield_population(j,y)=sum(yield_population_temp(j,y));

                abundance_population_temp(j,y,a,r)=abundance_at_age_AM(j,r,y,a);
                abundance_population(j,y,a)=sum(abundance_population_temp(j,y,a));
                abundance_total_temp(y,a,j)=abundance_population(j,y,a);
                abundance_total(y,a)=sum(abundance_total_temp(y,a));
                catch_at_age_total_temp(y,a,j)=catch_at_age_population(j,y,a);
                catch_at_age_total(y,a)=sum(catch_at_age_total_temp(y,a));
                yield_total_temp(y,j)=yield_population(j,y);
                yield_total(y)=sum(yield_total_temp(y));
                harvest_rate_region_num(j,r,y,a)=catch_at_age_region(j,r,y,a)/abundance_at_age_AM(j,r,y,a);
                harvest_rate_population_num(j,y,a)=catch_at_age_population(j,y,a)/abundance_population(j,y,a);
                harvest_rate_total_num(y,a)=catch_at_age_total(y,a)/abundance_total(y,a);
                harvest_rate_region_bio(j,r,y)=yield_region(j,r,y)/biomass_AM(j,r,y);
                harvest_rate_population_bio(j,y)=yield_population(j,y)/biomass_population(j,y);
                harvest_rate_total_bio(y)=yield_total(y)/biomass_total(y);
                depletion_region(j,r,y)=biomass_AM(j,r,y)/biomass_AM(j,r,1);
                depletion_population(j,y)=biomass_population(j,y)/biomass_population(j,1);
                depletion_total(y)=biomass_total(y)/biomass_total(1);
          } //end a==2 loop
  
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////a>2 a<nages overlap calcs////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
 
             if(a>2 && a<nages)
               {
                abundance_spawn_overlap(p,j,r,y,a)=abundance_at_age_AM_overlap_region(p,j,y,a,r)*mfexp(-(M(j,r,y,a)+F(j,r,y,a))*tspawn(p));
                abundance_natal_temp_overlap(p,y,a,j)=abundance_at_age_AM_overlap_population(p,j,y,a);
                abundance_natal_overlap(p,y,a)=sum(abundance_natal_temp_overlap(p,y,a));
                catch_at_age_region_fleet_overlap(p,j,r,z,y,a)=abundance_at_age_AM_overlap_region(p,j,y,a,r)*(1.0-mfexp(-(F_fleet(j,r,y,a,z)+M(j,r,y,a))))*(F_fleet(j,r,y,a,z)/(F_fleet(j,r,y,a,z)+M(j,r,y,a)));              
                yield_region_fleet_temp_overlap(p,j,r,z,y,a)=weight_catch(p,r,y,a)*catch_at_age_region_fleet_overlap(p,j,r,z,y,a);
                yield_region_fleet_overlap(p,j,r,z,y)=sum(yield_region_fleet_temp_overlap(p,j,r,z,y));
                catch_at_age_region_overlap(p,j,r,y,a)=abundance_at_age_AM_overlap_region(p,j,y,a,r)*(1.0-exp(-(F(j,r,y,a)+M(j,r,y,a))))*(F(j,r,y,a)/(F(j,r,y,a)+M(j,r,y,a)));
                yield_region_temp_overlap(p,j,r,y,a)=weight_catch(p,r,y,a)*catch_at_age_region_overlap(p,j,r,y,a);
                yield_region_overlap(p,j,r,y)=sum(yield_region_temp_overlap(p,j,r,y));
                catch_at_age_population_temp_overlap(p,j,y,a,r)=catch_at_age_region_overlap(p,j,r,y,a);
                catch_at_age_population_overlap(p,j,y,a)=sum(catch_at_age_population_temp_overlap(p,j,y,a));
                yield_population_temp_overlap(p,j,y,a)=weight_catch(p,r,y,a)*catch_at_age_population_overlap(p,j,y,a);
                yield_population_overlap(p,j,y)=sum(yield_population_temp_overlap(p,j,y));
                catch_at_age_natal_temp_overlap(p,y,a,j)=catch_at_age_population_overlap(p,j,y,a);
                catch_at_age_natal_overlap(p,y,a)=sum(catch_at_age_natal_temp_overlap(p,y,a));
                yield_natal_temp_overlap(p,y,j)=yield_population_overlap(p,j,y);
                yield_natal_overlap(p,y)=sum(yield_natal_temp_overlap(p,y));
                harvest_rate_region_fleet_bio_overlap(p,j,r,z,y)=yield_region_fleet_overlap(p,j,r,z,y)/biomass_AM_overlap_region(p,j,r,y);
                harvest_rate_region_bio_overlap(p,j,r,y)=yield_region_overlap(p,j,r,y)/biomass_AM_overlap_region(p,j,r,y);
                harvest_rate_population_bio_overlap(p,j,y)=yield_population_overlap(p,j,y)/biomass_population_overlap(p,j,y);
                harvest_rate_natal_bio_overlap(p,y)=yield_natal_overlap(p,y)/biomass_natal_overlap(p,y);
                depletion_region_overlap(p,j,r,y)=biomass_AM_overlap_region(p,j,r,y)/biomass_AM_overlap_region(p,j,r,1);
                depletion_population_overlap(p,j,y)=biomass_population_overlap(p,j,y)/biomass_population_overlap(p,j,1);
                depletion_natal_overlap(p,y)=biomass_natal_overlap(p,y)/biomass_natal_overlap(p,1);
                                
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////a>2 a<nages metapop type abundance calcs///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////   
                  abundance_spawn(j,r,y,a)=abundance_at_age_AM(j,r,y,a)*mfexp(-(M(j,r,y,a)+F(j,r,y,a))*tspawn(j));
                  catch_at_age_fleet(j,r,y,a,z)=abundance_at_age_AM(j,r,y,a)*(1.0-exp(-(F_fleet(j,r,y,a,z)+M(j,r,y,a))))*(F_fleet(j,r,y,a,z))/(F(j,r,y,a)+M(j,r,y,a));
                  yield_fleet_temp(j,r,y,z,a)=weight_catch(j,r,y,a)*catch_at_age_fleet(j,r,y,a,z);
                  yield_fleet(j,r,y,z)=sum(yield_fleet_temp(j,r,y,z));
                  catch_at_age_region(j,r,y,a)=sum(catch_at_age_fleet(j,r,y,a));
                  yield_region_temp(j,r,y,a)=weight_catch(j,r,y,a)*catch_at_age_region(j,r,y,a);
                  yield_region(j,r,y)=sum(yield_region_temp(j,r,y));
                  catch_at_age_population_temp(j,y,a,r)=catch_at_age_region(j,r,y,a);
                  catch_at_age_population(j,y,a)=sum(catch_at_age_population_temp(j,y,a));
                  yield_population_temp(j,y,a)=weight_catch(j,r,y,a)*catch_at_age_population(j,y,a);
                  yield_population(j,y)=sum(yield_population_temp(j,y));

                abundance_population_temp(j,y,a,r)=abundance_at_age_AM(j,r,y,a);
                abundance_population(j,y,a)=sum(abundance_population_temp(j,y,a));
                abundance_total_temp(y,a,j)=abundance_population(j,y,a);
                abundance_total(y,a)=sum(abundance_total_temp(y,a));
                catch_at_age_total_temp(y,a,j)=catch_at_age_population(j,y,a);
                catch_at_age_total(y,a)=sum(catch_at_age_total_temp(y,a));
                yield_total_temp(y,j)=yield_population(j,y);
                yield_total(y)=sum(yield_total_temp(y));
                harvest_rate_region_num(j,r,y,a)=catch_at_age_region(j,r,y,a)/abundance_at_age_AM(j,r,y,a);
                harvest_rate_population_num(j,y,a)=catch_at_age_population(j,y,a)/abundance_population(j,y,a);
                harvest_rate_total_num(y,a)=catch_at_age_total(y,a)/abundance_total(y,a);
                harvest_rate_region_bio(j,r,y)=yield_region(j,r,y)/biomass_AM(j,r,y);
                harvest_rate_population_bio(j,y)=yield_population(j,y)/biomass_population(j,y);
                harvest_rate_total_bio(y)=yield_total(y)/biomass_total(y);
                depletion_region(j,r,y)=biomass_AM(j,r,y)/biomass_AM(j,r,1);
                depletion_population(j,y)=biomass_population(j,y)/biomass_population(j,1);
                depletion_total(y)=biomass_total(y)/biomass_total(1);
       } //end a>2 <nages loop

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////a==nages overlap calcs////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
           if(a==nages) //account for fish already in plus group
            {
                abundance_spawn_overlap(p,j,r,y,a)=abundance_at_age_AM_overlap_region(p,j,y,a,r)*mfexp(-(M(j,r,y,a)+F(j,r,y,a))*tspawn(p));
                abundance_natal_temp_overlap(p,y,a,j)=abundance_at_age_AM_overlap_population(p,j,y,a);
                abundance_natal_overlap(p,y,a)=sum(abundance_natal_temp_overlap(p,y,a));
                catch_at_age_region_fleet_overlap(p,j,r,z,y,a)=abundance_at_age_AM_overlap_region(p,j,y,a,r)*(1.0-mfexp(-(F_fleet(j,r,y,a,z)+M(j,r,y,a))))*(F_fleet(j,r,y,a,z)/(F_fleet(j,r,y,a,z)+M(j,r,y,a)));              
                yield_region_fleet_temp_overlap(p,j,r,z,y,a)=weight_catch(p,r,y,a)*catch_at_age_region_fleet_overlap(p,j,r,z,y,a);
                yield_region_fleet_overlap(p,j,r,z,y)=sum(yield_region_fleet_temp_overlap(p,j,r,z,y));
                catch_at_age_region_overlap(p,j,r,y,a)=abundance_at_age_AM_overlap_region(p,j,y,a,r)*(1.0-exp(-(F(j,r,y,a)+M(j,r,y,a))))*(F(j,r,y,a)/(F(j,r,y,a)+M(j,r,y,a)));
                yield_region_temp_overlap(p,j,r,y,a)=weight_catch(p,r,y,a)*catch_at_age_region_overlap(p,j,r,y,a);
                yield_region_overlap(p,j,r,y)=sum(yield_region_temp_overlap(p,j,r,y));
                catch_at_age_population_temp_overlap(p,j,y,a,r)=catch_at_age_region_overlap(p,j,r,y,a);
                catch_at_age_population_overlap(p,j,y,a)=sum(catch_at_age_population_temp_overlap(p,j,y,a));
                yield_population_temp_overlap(p,j,y,a)=weight_catch(p,r,y,a)*catch_at_age_population_overlap(p,j,y,a);
                yield_population_overlap(p,j,y)=sum(yield_population_temp_overlap(p,j,y));
                catch_at_age_natal_temp_overlap(p,y,a,j)=catch_at_age_population_overlap(p,j,y,a);
                catch_at_age_natal_overlap(p,y,a)=sum(catch_at_age_natal_temp_overlap(p,y,a));
                yield_natal_temp_overlap(p,y,j)=yield_population_overlap(p,j,y);
                yield_natal_overlap(p,y)=sum(yield_natal_temp_overlap(p,y));
                harvest_rate_region_fleet_bio_overlap(p,j,r,z,y)=yield_region_fleet_overlap(p,j,r,z,y)/biomass_AM_overlap_region(p,j,r,y);
                harvest_rate_region_bio_overlap(p,j,r,y)=yield_region_overlap(p,j,r,y)/biomass_AM_overlap_region(p,j,r,y);
                harvest_rate_population_bio_overlap(p,j,y)=yield_population_overlap(p,j,y)/biomass_population_overlap(p,j,y);
                harvest_rate_natal_bio_overlap(p,y)=yield_natal_overlap(p,y)/biomass_natal_overlap(p,y);
                depletion_region_overlap(p,j,r,y)=biomass_AM_overlap_region(p,j,r,y)/biomass_AM_overlap_region(p,j,r,1);
                depletion_population_overlap(p,j,y)=biomass_population_overlap(p,j,y)/biomass_population_overlap(p,j,1);
                depletion_natal_overlap(p,y)=biomass_natal_overlap(p,y)/biomass_natal_overlap(p,1);               
                 
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////a==nages metapop type abundance calcs///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
     
                  abundance_spawn(j,r,y,a)=abundance_at_age_AM(j,r,y,a)*mfexp(-(M(j,r,y,a)+F(j,r,y,a))*tspawn(j));
                  catch_at_age_fleet(j,r,y,a,z)=abundance_at_age_AM(j,r,y,a)*(1.0-exp(-(F_fleet(j,r,y,a,z)+M(j,r,y,a))))*(F_fleet(j,r,y,a,z))/(F(j,r,y,a)+M(j,r,y,a));
                  yield_fleet_temp(j,r,y,z,a)=weight_catch(j,r,y,a)*catch_at_age_fleet(j,r,y,a,z);
                  yield_fleet(j,r,y,z)=sum(yield_fleet_temp(j,r,y,z));
                  catch_at_age_region(j,r,y,a)=sum(catch_at_age_fleet(j,r,y,a));
                  yield_region_temp(j,r,y,a)=weight_catch(j,r,y,a)*catch_at_age_region(j,r,y,a);
                  yield_region(j,r,y)=sum(yield_region_temp(j,r,y));
                  catch_at_age_population_temp(j,y,a,r)=catch_at_age_region(j,r,y,a);
                  catch_at_age_population(j,y,a)=sum(catch_at_age_population_temp(j,y,a));
                  yield_population_temp(j,y,a)=weight_catch(j,r,y,a)*catch_at_age_population(j,y,a);
                  yield_population(j,y)=sum(yield_population_temp(j,y));

                abundance_population_temp(j,y,a,r)=abundance_at_age_AM(j,r,y,a);
                abundance_population(j,y,a)=sum(abundance_population_temp(j,y,a));
                abundance_total_temp(y,a,j)=abundance_population(j,y,a);
                abundance_total(y,a)=sum(abundance_total_temp(y,a));
                catch_at_age_total_temp(y,a,j)=catch_at_age_population(j,y,a);
                catch_at_age_total(y,a)=sum(catch_at_age_total_temp(y,a));
                yield_total_temp(y,j)=yield_population(j,y);
                yield_total(y)=sum(yield_total_temp(y));
                harvest_rate_region_num(j,r,y,a)=catch_at_age_region(j,r,y,a)/abundance_at_age_AM(j,r,y,a);
                harvest_rate_population_num(j,y,a)=catch_at_age_population(j,y,a)/abundance_population(j,y,a);
                harvest_rate_total_num(y,a)=catch_at_age_total(y,a)/abundance_total(y,a);
                harvest_rate_region_bio(j,r,y)=yield_region(j,r,y)/biomass_AM(j,r,y);
                harvest_rate_population_bio(j,y)=yield_population(j,y)/biomass_population(j,y);
                harvest_rate_total_bio(y)=yield_total(y)/biomass_total(y);
                depletion_region(j,r,y)=biomass_AM(j,r,y)/biomass_AM(j,r,1);
                depletion_population(j,y)=biomass_population(j,y)/biomass_population(j,1);
                depletion_total(y)=biomass_total(y)/biomass_total(1);
        } //end nages if statement

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////SSB calcs////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


   //don't adjust SSB for fish not in natal population area because SR calculationp do this automatically by only using
   //SSB that is in natal population area (i.e., p==j)
   //for spawning migrationp scenarios the SSB is adjusted outside the loop to remove SSB of fish that actually returned
   // to natal population (i.e., remove this SSB from the non-natal areas...doesn't impact SR calcs so can do this outside
   //loops without conpequence to model
   
                SSB_region_temp_overlap(p,j,r,y,a)=abundance_spawn_overlap(p,j,r,y,a)*wt_mat_mult_reg(p,r,y,a); //added region
                SSB_region_overlap(p,j,r,y)=sum(SSB_region_temp_overlap(p,j,r,y));
                 SSB_overlap_natal=0;
                  if(natal_homing_switch==1 && spawn_return_switch==1) //spawning return calculationp
                   {
                    for(int k=1;k<=npops;k++)
                     {
                      for (int n=1;n<=nregions(k);n++)
                       {
                        if(p==k && j==k)
                         {
                          SSB_overlap_natal(k,n)=0;
                         }   
                        if(p==j && j!=k)
                         {
                          SSB_overlap_natal(k,n)=spawn_return_prob(p)*SSB_region_overlap(p,k,n,y);
                         } 
                       }
                      } 
                      if(p==j)
                      {
                       SSB_region_overlap(p,j,r,y)=SSB_region_overlap(p,j,r,y)+(sum(SSB_overlap_natal)/nregions(p));
                       }
                   } 
                SSB_population_temp_overlap(p,j,y,r)=SSB_region_overlap(p,j,r,y); 
                SSB_population_overlap(p,j,y)=sum(SSB_population_temp_overlap(p,j,y));
                SSB_natal_overlap_temp(p,y,j)=SSB_population_overlap(p,j,y);
                SSB_natal_overlap(p,y)=sum(SSB_natal_overlap_temp(p,y));  /// this is adjusted below outside y loop to account for fish not spawning

              if(natal_homing_switch>0)
               {
               if(p==j)  //accounts for not being in natal area
               {
                SSB_region(j,r,y)=SSB_region_overlap(p,j,r,y);
               }
              }
              if(natal_homing_switch==0)
              {
                SSB_region_temp(j,r,y,a)=abundance_spawn(j,r,y,a)*wt_mat_mult_reg(j,r,y,a); 
                SSB_region(j,r,y)=sum(SSB_region_temp(j,r,y));
              }
                SSB_population_temp(j,y,r)=SSB_region(j,r,y);
                SSB_population(j,y)=sum(SSB_population_temp(j,y));
                SSB_total_temp(y,j)=SSB_population(j,y);
                SSB_total(y)=sum(SSB_total_temp(y));

                Bratio_population_overlap(p,j,y)=SSB_population_overlap(p,j,y)/SSB_zero(p);
                Bratio_natal_overlap(p,y)=SSB_natal_overlap(p,y)/SSB_zero(p);
                Bratio_population(j,y)=SSB_population(j,y)/SSB_zero(j);
                Bratio_total(y)=SSB_total(y)/sum(SSB_zero);

                //YIELD observation error
                OBS_yield_region_fleet_overlap(p,j,r,y,z)=yield_region_fleet_overlap(p,j,r,z,y)*mfexp(yield_RN_overlap(p,j,r,y,z)*sigma_catch_overlap(p,j,r,z)-.5*square(sigma_catch_overlap(p,j,r,z)));
                OBS_yield_fleet_temp(j,r,y,z,p)=OBS_yield_region_fleet_overlap(p,j,r,y,z);
               if(natal_homing_switch==0)
                {
                 OBS_yield_fleet(j,r,y,z)=yield_fleet(j,r,y,z)*mfexp(yield_RN(j,r,y,z)*sigma_catch(j,r,z)-.5*square(sigma_catch(j,r,z)));
                }
               if(natal_homing_switch==1)
                {
                 OBS_yield_fleet(j,r,y,z)=sum(OBS_yield_fleet_temp(j,r,y,z));  
                }
                OBS_yield_region_overlap(p,j,y,r)=sum(OBS_yield_region_fleet_overlap(p,j,r,y));
                OBS_yield_population_overlap(p,y,j)=sum(OBS_yield_region_overlap(p,j,y));
                OBS_yield_natal_overlap(y,p)=sum(OBS_yield_population_overlap(p,y));
                OBS_yield_total_overlap(y)=sum(OBS_yield_natal_overlap(y));
                OBS_yield_region(j,y,r)=sum(OBS_yield_fleet(j,r,y));
                OBS_yield_population(y,j)=sum(OBS_yield_region(j,y));
                OBS_yield_total(y)=sum(OBS_yield_population(y));
             //apportion variables
                apport_yield_region(j,r,y)=OBS_yield_region(j,y,r)/OBS_yield_population(y,j);

          } //end fleets loop
             for (int z=1;z<=nfleets_survey(j);z++)    /// survey index  1. Currently set up for more than 1 survey fleet
              {
               if(tsurvey(j,r)>0) //if survey at beggining of year, do calcs without temporal adjustment for mortality
                {
                  true_survey_fleet_overlap_age(p,j,r,y,z,a)=survey_selectivity(j,r,y,a,z)*abundance_at_age_AM_overlap_region(p,j,y,a,r)*mfexp(-(M(j,r,y,a)+F(j,r,y,a))*tsurvey(j,r))*q_survey(j,r,z);
                  true_survey_fleet_overlap_age_bio(p,j,r,y,z,a)=true_survey_fleet_overlap_age(p,j,r,y,z,a)*weight_population(p,r,y,a);
                  true_survey_fleet_bio_overlap(p,j,r,y,z)=sum(true_survey_fleet_overlap_age_bio(p,j,r,y,z));  
                  true_survey_fleet_bio_overlap_temp(j,r,y,z,p)=true_survey_fleet_bio_overlap(p,j,r,y,z);
                  OBS_survey_fleet_bio_overlap(p,j,r,y,z)=true_survey_fleet_bio_overlap(p,j,r,y,z)*mfexp(survey_RN_overlap(p,j,r,y,z)*sigma_survey_overlap(p,j,r,z)-.5*square(sigma_survey_overlap(p,j,r,z)));
                  OBS_survey_fleet_bio_temp(j,r,y,z,p)=OBS_survey_fleet_bio_overlap(p,j,r,y,z);

                if(natal_homing_switch==0)
                 {
                  true_survey_fleet_age(j,r,y,z,a)=survey_selectivity(j,r,y,a,z)*abundance_at_age_AM(j,r,y,a)*mfexp(-(M(j,r,y,a)+F(j,r,y,a))*tsurvey(j,r))*q_survey(j,r,z);
                  true_survey_fleet_age_bio(j,r,y,z,a)=true_survey_fleet_age(j,r,y,z,a)*weight_population(j,r,y,a);                  
                  true_survey_fleet_bio(j,r,y,z)=sum(true_survey_fleet_age_bio(j,r,y,z));
                  OBS_survey_fleet_bio(j,r,y,z)=true_survey_fleet_bio(j,r,y,z)*mfexp(survey_RN(j,r,y,z)*sigma_survey(j,r,z)-.5*square(sigma_survey(j,r,z)));
                 }
                if(natal_homing_switch==1)
                 {
                  true_survey_fleet_bio(j,r,y,z)=sum(true_survey_fleet_bio_overlap_temp(j,r,y,z));
                  OBS_survey_fleet_bio(j,r,y,z)=sum(OBS_survey_fleet_bio_temp(j,r,y,z));  
                 }
             
                  true_survey_region_bio_overlap(p,j,y,r)=sum(true_survey_fleet_bio_overlap(p,j,r,y));               
                  true_survey_population_bio_overlap(p,y,j)=sum(true_survey_region_bio_overlap(p,j,y));               
                  true_survey_natal_bio_overlap(y,p)=sum(true_survey_population_bio_overlap(p,y));               
                  true_survey_total_bio_overlap(y)=sum(true_survey_natal_bio_overlap(y));
                  OBS_survey_region_bio_overlap(p,j,y,r)=sum(OBS_survey_fleet_bio_overlap(p,j,r,y));
                  OBS_survey_population_bio_overlap(p,y,j)=sum(OBS_survey_region_bio_overlap(p,j,y));
                  OBS_survey_natal_bio_overlap(y,p)=sum(OBS_survey_population_bio_overlap(p,y));
                  OBS_survey_total_bio_overlap(y)=sum(OBS_survey_natal_bio_overlap(y));
                  
                  true_survey_region_bio(j,y,r)=sum(true_survey_fleet_bio(j,r,y));
                  true_survey_population_bio(y,j)=sum(true_survey_region_bio(j,y));
                  true_survey_total_bio(y)=sum(true_survey_population_bio(y));
                  OBS_survey_region_bio(j,y,r)=sum(OBS_survey_fleet_bio(j,r,y));
                  OBS_survey_population_bio(y,j)=sum(OBS_survey_region_bio(j,y));
                  OBS_survey_total_bio(y)=sum(OBS_survey_population_bio(y));

                  apport_region_survey_biomass(j,r,y)=OBS_survey_region_bio(j,y,r)/OBS_survey_population_bio(y,j);
                  
                }  //tsurvey>0
               } //end survey_fleets
      }
     }
    }
   } // end age loop
  } //end yr>1 loop
 }  //end y loop



/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/////now adjusting natal homing ssb for spawning migration scenarios where fish left non-natal area
       for (int p=1;p<=npops;p++)
        {
         for (int j=1;j<=npops;j++)
          {
           for (int r=1;r<=nregions(p);r++)
            {
             for (int t=1;t<=nregions(j);t++)
              {
               for (int y=1;y<=nyrs;y++)
                {
                 SSB_overlap_natal=0;
                  if(natal_homing_switch==1 && spawn_return_switch==1)
                    {
                    if(p!=j)  //update SSB that doesn't spawn (ie doesn't return to natal population)
                    {
                     SSB_region_overlap(p,j,r,y)=(1-spawn_return_prob(p))*SSB_region_overlap(p,j,r,y);
                    }
                   SSB_population_temp_overlap(p,j,y,r)=SSB_region_overlap(p,j,r,y); 
                   SSB_population_overlap(p,j,y)=sum(SSB_population_temp_overlap(p,j,y));
                   SSB_natal_overlap_temp(p,y,j)=SSB_population_overlap(p,j,y);
                   SSB_natal_overlap(p,y)=sum(SSB_natal_overlap_temp(p,y));
                Bratio_population_overlap(p,j,y)=SSB_population_overlap(p,j,y)/SSB_zero(p);
                Bratio_natal_overlap(p,y)=SSB_natal_overlap(p,y)/SSB_zero(p);
                Bratio_population(j,y)=SSB_population(j,y)/SSB_zero(j);
                Bratio_total(y)=SSB_total(y)/sum(SSB_zero);
                    }
                   }
                  }
                 }
                }
               }
FUNCTION get_rand_survey_CAA_prop
 random_number_generator myrand_survey_age(myseed_survey_age);
 
  for (int p=1;p<=npops;p++)
   {
    for (int j=1;j<=npops;j++)
     {
      for (int r=1;r<=nregions(j);r++)
       {
        for (int z=1;z<=nfleets_survey(j);z++)
         {
          for (int y=1;y<=nyrs;y++) //need to alter to fit number of years of catch data
           {
            for (int a=1;a<=nages;a++)
             {
              survey_at_age_region_fleet_overlap_prop(p,j,r,z,y,a)=true_survey_fleet_overlap_age(p,j,r,y,z,a)/sum(true_survey_fleet_overlap_age(p,j,r,y,z));              
              survey_at_age_fleet_prop(j,r,y,z,a)=true_survey_fleet_age(j,r,y,z,a)/sum(true_survey_fleet_age(j,r,y,z));
             }
            }
           }
          }
         }
        }

  for (int p=1;p<=npops;p++)
   {
    for (int j=1;j<=npops;j++)
     {
      for (int r=1;r<=nregions(j);r++)
       {
        for (int z=1;z<=nfleets_survey(j);z++)
         {
          for (int y=1;y<=nyrs;y++) //need to alter to fit number of years of catch data
           {
            if(use_stock_comp_info_survey==0)
             {
              rand_SIM_survey_prop_temp(j,r,y,z).fill_multinomial(myrand_survey_age,(survey_at_age_fleet_prop(j,r,y,z)));
             }
            if(use_stock_comp_info_survey==1)
             {
              rand_SIM_survey_prop_temp_overlap(p,j,r,y,z).fill_multinomial(myrand_survey_age,(survey_at_age_region_fleet_overlap_prop(p,j,r,z,y)));
             }
           }
         }
       }
     }
   }

  for (int p=1;p<=npops;p++)
   {
    for (int j=1;j<=npops;j++)
     {
      for (int r=1;r<=nregions(j);r++)
       {
        for (int z=1;z<=nfleets_survey(j);z++)
         {
          for (int y=1;y<=nyrs;y++) //need to alter to fit number of years of catch data
           {
             rand_SIM_survey_prop_temp2=0;
            if(use_stock_comp_info_survey==0)
             {
               for(int n=1;n<=SIM_nsurvey(j,r,z);n++) 
                {
                 rand_SIM_survey_prop_temp2((rand_SIM_survey_prop_temp(j,r,y,z,n)))+= 1.0;
                }
               SIM_survey_prop(j,r,z,y)=rand_SIM_survey_prop_temp2;
             }
            if(use_stock_comp_info_survey==1)
             {              
               for(int n=1;n<=SIM_nsurvey_overlap(p,j,r,z);n++) /// look into changing this so can have ncatch change by year (ie different sample sizes for beginning and end of timeseries)
                {
                 rand_SIM_survey_prop_temp2((rand_SIM_survey_prop_temp_overlap(p,j,r,y,z,n)))+= 1.0;
                }
               SIM_survey_prop_overlap(p,j,r,z,y)=rand_SIM_survey_prop_temp2;
             }
             
        for(int a=1;a<=nages;a++)
         {
          if(use_stock_comp_info_survey==0)
           {
            OBS_survey_prop(j,r,z,y,a)=SIM_survey_prop(j,r,z,y,a)/SIM_nsurvey(j,r,z);
           }
          if(use_stock_comp_info_survey==1)
           {
            OBS_survey_prop_overlap(p,j,r,z,y,a)=SIM_survey_prop_overlap(p,j,r,z,y,a)/SIM_nsurvey_overlap(p,j,r,z);
           }
         }
       }
      }
     }
    }
   }

FUNCTION get_rand_CAA_prop
 random_number_generator myrand_catch_age(myseed_catch_age);
 
  for (int p=1;p<=npops;p++)
   {
    for (int j=1;j<=npops;j++)
     {
      for (int r=1;r<=nregions(j);r++)
       {
        for (int z=1;z<=nfleets(j);z++)
         {
          for (int y=1;y<=nyrs;y++) //need to alter to fit number of years of catch data
           {
            for (int a=1;a<=nages;a++)
             {
                 catch_at_age_region_fleet_overlap_prop(p,j,r,z,y,a)=catch_at_age_region_fleet_overlap(p,j,r,z,y,a)/sum(catch_at_age_region_fleet_overlap(p,j,r,z,y));              
                 catch_at_age_region_overlap_prop(p,j,r,y,a)=catch_at_age_region_overlap(p,j,r,y,a)/sum(catch_at_age_region_overlap(p,j,r,y));
                 catch_at_age_population_overlap_prop(p,j,y,a)=catch_at_age_population_overlap(p,j,y,a)/sum(catch_at_age_population_overlap(p,j,y));
                 catch_at_age_natal_overlap_prop(p,y,a)=catch_at_age_natal_overlap(p,y,a)/sum(catch_at_age_natal_overlap(p,y));

                 catch_at_age_fleet_prop_temp(j,r,y,z,a)=catch_at_age_fleet(j,r,y,a,z);
                 catch_at_age_fleet_prop(j,r,y,z,a)=catch_at_age_fleet_prop_temp(j,r,y,z,a)/sum(catch_at_age_fleet_prop_temp(j,r,y,z));
                 catch_at_age_region_prop(j,r,y,a)=catch_at_age_region(j,r,y,a)/sum(catch_at_age_region(j,r,y));
                 catch_at_age_population_prop(j,y,a)=catch_at_age_population(j,y,a)/sum(catch_at_age_population(j,y));
                 catch_at_age_total_prop(y,a)=catch_at_age_total(y,a)/sum(catch_at_age_total(y));
              }
            }
           }
          }
         }
        }
        
  for (int p=1;p<=npops;p++)
   {
    for (int j=1;j<=npops;j++)
     {
      for (int r=1;r<=nregions(j);r++)
       {
        for (int z=1;z<=nfleets(j);z++)
         {
          for (int y=1;y<=nyrs;y++) //need to alter to fit number of years of catch data
           {
            if(use_stock_comp_info_catch==0)
             {
              rand_SIM_catch_prop_temp(j,r,y,z).fill_multinomial(myrand_catch_age,(catch_at_age_fleet_prop(j,r,y,z)));
             }
            if(use_stock_comp_info_catch==1)
             {
              rand_SIM_catch_prop_temp_overlap(p,j,r,y,z).fill_multinomial(myrand_catch_age,(catch_at_age_region_fleet_overlap_prop(p,j,r,z,y)));
             }
           }
         }
       }
     }
   }
            
  for (int p=1;p<=npops;p++)
   {
    for (int j=1;j<=npops;j++)
     {
      for (int r=1;r<=nregions(j);r++)
       {
        for (int z=1;z<=nfleets(j);z++)
         {
          for (int y=1;y<=nyrs;y++) //need to alter to fit number of years of catch data
           {
             rand_SIM_catch_prop_temp2=0;

            if(use_stock_comp_info_catch==0)
             {
               for(int n=1;n<=SIM_ncatch(j,r,z);n++) /// look into changing this so can have ncatch change by year (ie different sample sizes for beginning and end of timeseries)
                {
                 rand_SIM_catch_prop_temp2((rand_SIM_catch_prop_temp(j,r,y,z,n)))+= 1.0;
                }
               SIM_catch_prop(j,r,z,y)=rand_SIM_catch_prop_temp2;
             }
            if(use_stock_comp_info_catch==1)
             {              
               for(int n=1;n<=SIM_ncatch_overlap(p,j,r,z);n++) /// look into changing this so can have ncatch change by year (ie different sample sizes for beginning and end of timeseries)
                {
                 rand_SIM_catch_prop_temp2((rand_SIM_catch_prop_temp_overlap(p,j,r,y,z,n)))+= 1.0;
                }
               SIM_catch_prop_overlap(p,j,r,z,y)=rand_SIM_catch_prop_temp2;
             }
             
        for(int a=1;a<=nages;a++)
         {
          if(use_stock_comp_info_catch==0)
           {
            OBS_catch_prop(j,r,z,y,a)=SIM_catch_prop(j,r,z,y,a)/SIM_ncatch(j,r,z);
           }
          if(use_stock_comp_info_catch==1)
           {
            OBS_catch_prop_overlap(p,j,r,z,y,a)=SIM_catch_prop_overlap(p,j,r,z,y,a)/SIM_ncatch_overlap(p,j,r,z);
           }
         }
       }
      }
     }
    }
   }

FUNCTION get_tag_recaptures
  ////////////////////////////////////////////////////////////////////////////
  ////////////////////////////////////////////////////////////////////////////
  ////////////////////////////////////////////////////////////////////////////
  // In some calcs (mortality and movement) need to account for true age (age+time at large),
  // because multiple cohorts this means need to factor in release year
  // so true age becomes age+year-release year
  // using subscript notation this equals= (a+y-xx)
  // similarly because account for release age, do not need to worry about plus group calcs as carry recaptures out to max_life_tags and never assume plus group (just use plus group mortality and movement values in calcs where a>=max_age)
  /////////////////////////////////////////////////////////////////////////////
 if(do_tag==1)
  {
//Calculate ntags released by population and region based on relative survey biomass among populations and regions and survey selectivity
 for (int i=1;i<=npops;i++)
  {
   for (int n=1;n<=nregions(i);n++)
    {
    for(int x=1; x<=nyrs_release; x++)
     {
      xx=yrs_releases(x);
      for (int a=1;a<=nages;a++) //release age 
        {
          ntags_total(x)=frac_total_abund_tagged(x)*sum(abundance_total(xx));
          ntags(i,n,x,a)=ntags_total(x)*(true_survey_population_bio(xx,i)/true_survey_total_bio(xx))*(true_survey_region_bio(i,xx,n)/true_survey_population_bio(xx,i))*survey_selectivity(i,n,xx,a,1);
        }
       }
      }
     }
 //assume tags released in natal population
 for (int i=1;i<=npops;i++)
  {
   for (int n=1;n<=nregions(i);n++)
    {
    for(int x=1; x<=nyrs_release; x++)
     {
      xx=yrs_releases(x);
      for (int a=1;a<=nages;a++) //release age //because accounting for release age, don't need to account for recap age, just adjust mortality and T, to use plus group value if recapture age exceeds max age
        {
         for(int y=1;y<=max_life_tags;y++)  //recap year
          {
           for(int j=1;j<=npops;j++) //recap stock
            {
             for (int r=1;r<=nregions(j);r++)
             {
              total_recap_temp(j,y,r)=0; //for whatever reason ADMB won't let a 3darray=double...this is workaround for total_recap_temp=0;, ie setting temp 3darray to 0 after loops through all years 
             }
            }
           }
         for(int y=1;y<=max_life_tags;y++)  //recap year
          {
           for(int j=1;j<=npops;j++) //recap stock
            {
             for (int r=1;r<=nregions(j);r++)
             {
              if(y==1) //year of release for a cohort
               {              
                 tags_avail(i,n,x,a,y,j,r)=ntags(i,n,x,a)*T(i,n,xx,a,j,r); 
                 recaps(i,n,x,a,y,j,r)=report_rate(j,x,r)*tags_avail(i,n,x,a,y,j,r)*F(j,r,xx,a)*(1.-mfexp(-(F(j,r,xx,a)+M(j,r,xx,a))))/(F(j,r,xx,a)+(M(j,r,xx,a)));  //recaps=tags available*fraction of fish that die*fraction of mortality due to fishing*tags inspected (reporting)                                
               }
              if(y>1) // must account for the maximum age so use min function to ensure that not exceeding the max age
              {
               tags_avail_temp=0;
               for(int p=1;p<=npops;p++)
               {
                for (int s=1;s<=nregions(p);s++)
                {
                 if(natal_homing_switch==0) //if no natal homing
                 {
                  tags_avail_temp(p,s)=tags_avail(i,n,x,a,y-1,p,s)*T(p,s,(xx+y-1),min((a+y),nages),j,r)*mfexp(-(F(p,s,(xx+y-2),min(((a+y)-1),nages))+(M(p,s,(xx+y-2),min(((a+y)-1),nages))))); //tags_temp holds all tags moving into population j,region r; min function takes min of true age and max age allowed (plus group)
                 }                        
                //#####################################################################################################
                //  TRUE NATAL HOMING  T(n,x,a,y,j) becomes T(i,x,a,y,j) because need to maintain your natal origin
                //  movement values so T doesn't depend on current population only origin population and destination population
                //########################################################################################################              
                 if(natal_homing_switch==1) //if natal homing 
                 {
                  tags_avail_temp(p,s)=tags_avail(i,n,x,a,y-1,p,s)*T(i,n,(xx+y-1),min((a+y),nages),j,r)*mfexp(-(F(p,s,(xx+y-2),min(((a+y)-1),nages))+(M(p,s,(xx+y-2),min(((a+y)-1),nages))))); //tags_temp holds all tags moving into population j,region r; min function takes min of true age and max age allowed (plus group)             
                 }               
                }
               }
                 tags_avail(i,n,x,a,y,j,r)=sum(tags_avail_temp); //sum across all pops/regs of tags that moved into pop j reg r
                 recaps(i,n,x,a,y,j,r)=report_rate(j,x,r)*tags_avail(i,n,x,a,y,j,r)*F(j,r,(xx+y-1),min((a+y),nages))*(1.-mfexp(-(F(j,r,(xx+y-1),min((a+y),nages))+(M(j,r,(xx+y-1),min((a+y),nages))))))/(F(j,r,(xx+y-1),min((a+y),nages))+(M(j,r,(xx+y-1),min((a+y),nages))));  //recaps=tags available*fraction of fish that die*fraction of mortality due to fishing*tags inspected (reporting)                 
               }
             total_recap_temp(j,y,r)=recaps(i,n,x,a,y,j,r);
             }
            }
           }
             total_rec(i,n,x,a)=sum(total_recap_temp);
             not_rec(i,n,x,a)=ntags(i,n,x,a)-total_rec(i,n,x,a);  //for ntags  at a given age all entries represent all tags released so can just use any of the entries (hence the i,x,a,1 subscripts)
           }
          }
         }
        }
 for (int i=1;i<=npops;i++)
  {
   for (int n=1;n<=nregions(i);n++)
    {
    for(int x=1; x<=nyrs_release; x++)
     {
      for (int a=1;a<=nages;a++) //release age //because accounting for release age, don't need to account for recap age, just adjust mortality and T, to use plus group value if recapture age exceeds max age
        {
         for(int y=1;y<=max_life_tags;y++)  //recap year
          {
           for(int j=1;j<=npops;j++) //recap stock
            {
             for (int r=1;r<=nregions(j);r++)
             {
              if(ntags(i,n,x,a)>0)
               {
                tag_prop(i,n,x,a,y,j,r)=recaps(i,n,x,a,y,j,r)/ntags(i,n,x,a);
                tag_prop_not_rec(i,n,x,a)=not_rec(i,n,x,a)/ntags(i,n,x,a);
               }
              if(ntags(i,n,x,a)==0)
               {                   
                tag_prop(i,n,x,a,y,j,r)=0;
                tag_prop_not_rec(i,n,x,a)=0;
               }
             } 
            }
           }
          }
         }
        }
       }

 //in order to use the multinomial RNG, need to have a vector of probabilities
 //this essentially requires stacking the tag_prop array into vectors for each release cohort covering all recap states (recap year, population, region)
 //need to extract each recap prob vector and store, then combine into array where can extract the last index (essentially the columns of the array)
 //can then use the fill.multinomial with that vector of probabilities


 nreg_temp=rowsum(nregions_temp);
 for (int i=1;i<=npops;i++)
  {
   for (int n=1;n<=nregions(i);n++)
    {
    for(int x=1; x<=nyrs_release; x++)
     {
       for (int a=1;a<=nages;a++) //release age 
        {
         for(int y=1;y<=max_life_tags;y++)  //recap year
          {
           for(int j=1;j<=npops;j++) //recap stock
            {
             for (int r=1;r<=nregions(j);r++)
             {
              tag_prop_temp(j,y,r)=0; //for whatever reason ADMB won't let a 3darray=double...this is workaround for total_recap_temp=0;, ie setting temp 3darray to 0 after loops through all years 
             }
            }
           }
         for(int y=1;y<=max_life_tags;y++)  //recap year
          {
           for(int j=1;j<=npops;j++) //recap stock
            {
             for (int r=1;r<=nregions(j);r++) //recap region
              {
               tag_prop_temp(j,y,r)=tag_prop(i,n,x,a,y,j,r); //fill temp array with a single release cohort's recapture probabilities (excluding not recaptured)
              }
            }
           }
         tag_prop_temp2=0;
         for(int y=1;y<=max_life_tags;y++)  //recap year
          {
           for(int j=1;j<=npops;j++) //recap stock
            {
             for (int r=1;r<=nregions(j);r++)
              {
               tag_prop_temp2(((y-1)*sum(nregions)+nreg_temp(j)+r))=tag_prop_temp(j,y,r); //stack array into single vector by year, population, region
              }
             }
            }
             for(int s=1;s<=(max_life_tags*sum(nregions)+1);s++) //create temp array that has columns of recap prob for each release cohort and add not recap probability to final entry of temp array
              {
              if(s<(max_life_tags*sum(nregions)+1))
              {
               tag_prop_final(i,n,x,a,s)=tag_prop_temp2(s);
              }
              if(s==(max_life_tags*sum(nregions)+1)) //add not recap probability to final entry of temp array
              {
               tag_prop_final(i,n,x,a,s)=tag_prop_not_rec(i,n,x,a);  //for estimation model will use this version of tag_prop in likelihood
              }
            }
           }
          }
         }
        }
 }
FUNCTION get_observed_tag_recaptures
 if(do_tag==1)
  {
  
 random_number_generator myrand_tag(myseed_tag);

 for (int i=1;i<=npops;i++)
  {
   for (int n=1;n<=nregions(i);n++)
    {
    for(int x=1; x<=nyrs_release; x++)
     {
       for (int a=1;a<=nages;a++) //release age 
        {
         rand_tag_prop_temp(i,n,x,a).fill_multinomial(myrand_tag,(tag_prop_final(i,n,x,a))); //fill multinomial using recap prop for each cohort
        }
       }
      }
     }
 for (int i=1;i<=npops;i++)
  {
   for (int n=1;n<=nregions(i);n++)
    {
    for(int x=1; x<=nyrs_release; x++)
     {
       for (int a=1;a<=nages;a++) //release age 
        {
          rand_tag_prop_temp2=0;
            for(int s=1;s<=SIM_ntag;s++) /// look into changing this so can have ntag change by year (ie different sample sizes for beginning and end of timeseries)
             {
               rand_tag_prop_temp2((rand_tag_prop_temp(i,n,x,a,s)))+= 1.0; //count up number in each recap state
              }
           SIM_tag_prop(i,n,x,a)=rand_tag_prop_temp2; //put number in each recap state into appropriate release cohort
        }
       }
      }
     }

 for (int i=1;i<=npops;i++)
  {
   for (int n=1;n<=nregions(i);n++)
    {
    for(int x=1; x<=nyrs_release; x++)
     {
       for (int a=1;a<=nages;a++) //release age 
        {
         for(int s=1;s<=(max_life_tags*sum(nregions)+1);s++) //create temp array that has columns of recap prob for each release cohort and add not recap probability to final entry of temp array
          {           
           OBS_tag_prop_final(i,n,x,a,s)=SIM_tag_prop(i,n,x,a,s)/SIM_ntag;
              if(ntags(i,n,x,a)==0)
               {                   
                OBS_tag_prop_final(i,n,x,a,s)=0;
               }
          }
        }
       }
      }
     }
 }
FUNCTION evaluate_the_objective_function
   f=0.0;

           for (int y=1;y<=nyrs;y++)
            {
             for (int j=1;j<=npops;j++)
              {
               for (int r=1;r<=nregions(j);r++)
                {
                 for (int z=1;z<=nfleets(j);z++)
                  {
                    res_TAC(j,r,z,y)=input_TAC(j,r,z)-yield_fleet(j,r,y,z);
                  }
                 res_u(j,r,y)=sum(input_u(j,r))-harvest_rate_region_bio(j,r,y);
                }
               }
              }


//dhdhdhdhdhdhdhdhdhhdhd
 //Started up some likelihood sections here
 // dhdhdhdhdhdhdhdhdhdhdh
FUNCTION Surv_Likelihood
 // Calculate likelihood for survey biomass
  surv_like.initialize();
  for (i=1; i<=nyrs_srv1; i++)  {   ii=yrs_srv1(i);
  surv_like(1) += square((log(obs_srv1_biom(i)+0.0001)-log(pred_srv1(ii)+0.0001) ))/ (2.*square(obs_srv1_se(i)/obs_srv1_biom(i))); }// log-likelihood for survey biomass
  for (i=1; i<=nyrs_srv2; i++)  {   ii=yrs_srv2(i);
  surv_like(2) += square((log(obs_srv2_biom(i)+0.0001)-log(pred_srv2(ii)+0.0001) ))/ (2.*square(obs_srv2_se(i)/obs_srv2_biom(i))); }
    // likelihood for survey biomass 
  surv_like(1) *= wt_srv1 ;  
  surv_like(2) *= wt_srv2 ;  
  
FUNCTION Multinomial_Likelihood
// Calculate multinomial likelihoods for compositions
  age_like.initialize();
  for (i=1; i <= nyrs_fish1_age; i++)
    age_like(1) -= nsamples_fish1_age(i)*((oac_fish1(i) + 0.001) * log(eac_fish1(i) + 0.001)) ;
  for (i=1; i <= nyrs_srv1_age; i++)
    age_like(2) -= nsamples_srv1_age(i)*((oac_srv1(i) + 0.001) * log(eac_srv1(i) + 0.001)) ;
  age_like(1) *= wt_fish1_age;                 // Multiple each likelihood by their weights from .ctl file
  age_like(2) *= wt_srv1_age;  

FUNCTION evaluate_the_objective_function
   f=0.0;

           for (int y=1;y<=nyrs;y++)
            {
             for (int j=1;j<=npops;j++)
              {
               for (int r=1;r<=nregions(j);r++)
                {
                 for (int z=1;z<=nfleets(j);z++)
                  {
                    res_TAC(j,r,z,y)=input_TAC(j,r,z)-yield_fleet(j,r,y,z);
                  }
                 res_u(j,r,y)=sum(input_u(j,r))-harvest_rate_region_bio(j,r,y);
                }
               }
              }
  obj_fun.initialize();
  ssqcatch.initialize();
  rec_like.initialize();
  Surv_Likelihood();                                  // Likelihood function for survey biomass
  ssqcatch  +=  wt_ssqcatch_fish1 *norm2(log(obs_catch_fish1+0.01)-log(pred_catch_fish1+0.01));
  rec_like      = wt_rec_var*(norm2(log_rec_dev+sigr*sigr/2.)/(2.*square(sigr)) + (size_count(log_rec_dev))*log(sigr));
  Multinomial_Likelihood();                           // Multinomial likelihood

// Sum objective function
  obj_fun           += ssqcatch ;
  obj_fun           += sum(surv_like);
  obj_fun           += sum(age_like);
  obj_fun           += rec_like;
  obj_fun_nb_admb-=log_negbinomial_density(recovered(i,j,t),recovered_pred(i,j,t)+1e-10,theta);  //negative binomial tag likelihood

REPORT_SECTION
 //report<<"$recaps"<<endl;
 //report<<recaps<<endl;
 report<<"$True_tag_prop"<<endl;
 report<<tag_prop_final<<endl;
 report<<"$OBS_tag_prop"<<endl;
 report<<OBS_tag_prop_final<<endl;
 // report<<"$biomass_BM_age"<<endl;
 // report<<biomass_BM_age<<endl;
 // report<<"$Fract_Move_DD"<<endl;
 // report<<Fract_Move_DD<<endl;
 // report<<"$T"<<endl;
 // report<<T<<endl;
 // report<<"$rel_bio"<<endl;
 // report<<rel_bio<<endl;
 report<<"$Fyear"<<endl;
 report<<F_year<<endl;

  report<<"$res_TAC"<<endl;
  report<<res_TAC<<endl;
  report<<"$res_u"<<endl;
  report<<res_u<<endl;
  //report<<"$myseed"<<endl;
  //report<<myseed<<endl;
  report<<"$nages"<<endl;
  report<<nages<<endl;
  report<<"$nyrs"<<endl;
  report<<nyrs<<endl;
  report<<"$npops"<<endl;
  report<<npops<<endl;
  report<<"$nregions"<<endl;
  report<<nregions<<endl;
  report<<"$nages"<<endl;
  report<<nages<<endl;
  report<<"$nfleets"<<endl;
  report<<nfleets<<endl;

  report<<"$larval_move_switch"<<endl;
  report<<larval_move_switch<<endl;
  report<<"$move_switch"<<endl;
  report<<move_switch<<endl;
  report<<"$natal_homing_switch"<<endl;
  report<<natal_homing_switch<<endl;
  report<<"$F_switch"<<endl;
  report<<F_switch<<endl;
  report<<"$recruit_devs_switch"<<endl;
  report<<recruit_devs_switch<<endl;
  report<<"$recruit_randwalk_switch"<<endl;
  report<<recruit_randwalk_switch<<endl;
  report<<"$SSB_type"<<endl;
  report<<SSB_type<<endl;
  report<<"$apportionment_type"<<endl;
  report<<apportionment_type<<endl;
  report<<"$Rec_type"<<endl;
  report<<Rec_type<<endl;
  report<<"$return_age"<<endl;
  report<<return_age<<endl;
  report<<"$return_probability"<<endl;
  report<<return_probability<<endl;
  report<<"$spawn_return_prob"<<endl;
  report<<spawn_return_prob<<endl;

  report<<"$tspawn"<<endl;
  report<<tspawn<<endl;
  report<<"$steep"<<endl;
  report<<steep<<endl;
  report<<"$R_ave"<<endl;
  report<<R_ave<<endl;
  report<<"$SSB_zero"<<endl;
  report<<SSB_zero<<endl;


  

//  report<<"$input_T"<<endl;
//  report<<input_T<<endl;
//  report<<"$input_residency"<<endl;
//  report<<input_residency<<endl;
//  report<<"$input_residency_larval"<<endl;
//  report<<input_residency_larval<<endl;
//  report<<"$sel_beta1"<<endl;
//  report<<sel_beta1<<endl;
//  report<<"$sel_beta2"<<endl;
//  report<<sel_beta2<<endl;
//  report<<"$sel_beta3"<<endl;
//  report<<sel_beta3<<endl;
//  report<<"$sel_beta4"<<endl;
//  report<<sel_beta4<<endl;
//  report<<"$input_selectivity"<<endl;
//  report<<input_selectivity<<endl;
//  report<<"$input_F"<<endl;
//  report<<input_F<<endl;
//  report<<"$input_F_MSY"<<endl;
//  report<<input_F_MSY<<endl;
//  report<<"$input_M"<<endl;
//  report<<input_M<<endl;
//  report<<"$sigma_recruit"<<endl;
//  report<<sigma_recruit<<endl;
//  report<<"$input_weight"<<endl;
//  report<<input_weight<<endl;
//  report<<"$input_catch_weight"<<endl;
//  report<<input_catch_weight<<endl;
//  report<<"$fecundity"<<endl;
//  report<<fecundity<<endl;
//  report<<"$maturity"<<endl;
//  report<<maturity<<endl;
//  report<<"$input_Rec_prop"<<endl;
//  report<<input_Rec_prop<<endl;
//  report<<"$init_abund"<<endl;
//  report<<init_abund<<endl;
//  report<<$"rec_index_sigma"<<end;
//  report<<rec_index_sigma<<end;

//  report<<"$F_est"<<endl;
//  report<<F_est<<endl;


//  report<<"$rec_devs"<<endl;
 // report<<rec_devs<<endl;
//  report<<"$weight_population"<<endl;
//  report<<weight_population<<endl;
//  report<<"$weight_catch"<<endl;
//  report<<weight_catch<<endl;
//  report<<"$wt_mat_mult"<<endl;
//  report<<wt_mat_mult<<endl;
//  report<<"$weight_population_overlap"<<endl;
//  report<<weight_population_overlap<<endl;
//  report<<"$weight_catch_overlap"<<endl;
//  report<<weight_catch_overlap<<endl;
//  report<<"$wt_mat_mult_overlap"<<endl;
//  report<<wt_mat_mult_overlap<<endl;
//  report<<"$Rec_Prop"<<endl;
//  report<<Rec_Prop<<endl;
//  report<<"$SPR_N"<<endl;
//  report<<SPR_N<<endl;
//  report<<"$SPR_SSB"<<endl;
// report<<SPR_SSB<<endl;

  report<<"$alpha"<<endl;
  report<<alpha<<endl;
  report<<"$beta"<<endl;
  report<<beta<<endl;


//  report<<"$abundance_at_age_BM"<<endl;
//  report<<abundance_at_age_BM<<endl;
//  report<<"$abundance_at_age_AM"<<endl;
//  report<<abundance_at_age_AM<<endl;
//  report<<"T"<<endl;
//  report<<T<<endl;
//  report<<"$abundance_AM_overlap_region_all_natal"<<endl;
//  report<<abundance_AM_overlap_region_all_natal<<endl;
//  report<<"$abundance_population"<<endl;
//  report<<abundance_population<<endl;
//  report<<"$abundance_total"<<endl;
//  report<<abundance_total<<endl;
//  report<<"$abundance_in"<<endl;
//  report<<abundance_in<<endl;
//  report<<"$abundance_res"<<endl;
//  report<<abundance_res<<endl;
//  report<<"$abundance_leave"<<endl;
//  report<<abundance_leave<<endl;
//  report<<"$abundance_spawn"<<endl;
//  report<<abundance_spawn<<endl;
//  report<<"$biomass_BM"<<endl;
//  report<<biomass_BM<<endl;
//  report<<"$biomass_BM_age"<<endl;
//  report<<biomass_BM_age<<endl;

//  report<<"$biomass_AM_age"<<endl;
//  report<<biomass_AM_age<<endl;

//  report<<"$bio_in"<<endl;
//  report<<bio_in<<endl;
//  report<<"$bio_res"<<endl;
//  report<<bio_res<<endl;
//  report<<"$bio_leave"<<endl;
//  report<<bio_leave<<endl;

//  report<<"$catch_at_age_fleet"<<endl;
//  report<<catch_at_age_fleet<<endl;
//  report<<"$catch_at_age_region"<<endl;
//  report<<catch_at_age_region<<endl;
//  report<<"$catch_at_age_population"<<endl;
//  report<<catch_at_age_population<<endl;
//  report<<"$catch_at_age_total"<<endl;
//  report<<catch_at_age_total<<endl;

//  report<<"$obs_caa_fleet"<<endl;
//  report<<obs_caa_fleet<<endl;
//  report<<"$obs_prop_fleet"<<endl;
//  report<<obs_prop_fleet<<endl;

//  report<<"$obs_caa_overlap_reg"<<endl;
//  report<<obs_caa_overlap_reg<<endl;
//  report<<"$obs_prop_overlap_reg"<<endl;
//  report<<obs_prop_overlap_reg<<endl;

 report<<"$recruits_BM"<<endl;
 report<<recruits_BM<<endl;
//  report<<"$rec_index_BM"<<endl;
//  report<<rec_index_BM<<endl;

//  report<<"$OBS_index_region<<endl;
//  report<<OBS_index_region<<endl;
//  report<<"$apport_region_survey<<endl;
//  report<<apport_region_survey<<endl;


//  report<<"$harvest_rate_region_num"<<endl;
//  report<<harvest_rate_region_num<<endl;
//  report<<"$harvest_rate_population_num"<<endl;
//  report<<harvest_rate_population_num<<endl;
//  report<<"$harvest_rate_total_num"<<endl;
//  report<<harvest_rate_total_num<<endl;

//  report<<"$residuals"<<endl;
//  report<<res<<endl;
//  report<<"$harvest_rate_pen"<<endl;
//  report<<harvest_rate_pen<<endl;

//  report<<"$abundance_at_age_BM_overlap_region"<<endl;
//  report<<abundance_at_age_BM_overlap_region<<endl;
//  report<<"$abundance_at_age_BM_overlap_population"<<endl;
//  report<<abundance_at_age_BM_overlap_population<<endl;
//  report<<"$abundance_at_age_AM_overlap_region"<<endl;
//  report<<abundance_at_age_AM_overlap_region<<endl;
//  report<<"$abundance_at_age_AM_overlap_population"<<endl;
//  report<<abundance_at_age_AM_overlap_population<<endl;
//  report<<"$abundance_natal_overlap"<<endl;
//  report<<abundance_natal_overlap<<endl;
//  report<<"$abundance_spawn_overlap"<<endl;
//  report<<abundance_spawn_overlap<<endl;



//  report<<"$catch_at_age_region_overlap"<<endl;
//  report<<catch_at_age_region_overlap<<endl;
//  report<<"$catch_at_age_population_overlap"<<endl;
//  report<<catch_at_age_population_overlap<<endl;
//  report<<"$catch_at_age_natal_overlap"<<endl;
//  report<<catch_at_age_natal_overlap<<endl;



//  report<<"$biomass_BM_overlap_region"<<endl;
//  report<<biomass_BM_overlap_region<<endl;
//  report<<"$biomass_BM_age_overlap"<<endl;
//  report<<biomass_BM_age_overlap<<endl;

 // report<<"$biomass_AM_age_overlap"<<endl;
//  report<<biomass_AM_age_overlap<<endl;


  report<<"$F"<<endl;
  report<<F<<endl;
  report<<"$M"<<endl;
  report<<M<<endl;

  report<<"$biomass_AM"<<endl;
  report<<biomass_AM<<endl;
  report<<"$biomass_population"<<endl;
  report<<biomass_population<<endl;
  report<<"$biomass_total"<<endl;
  report<<biomass_total<<endl;

  report<<"$yield_fleet"<<endl;
  report<<yield_fleet<<endl;
  report<<"$yield_region"<<endl;
  report<<yield_region<<endl;
  report<<"$TAC"<<endl;
  report<<TAC<<endl;
  report<<"$yield_population"<<endl;
  report<<yield_population<<endl;
  report<<"$yield_total"<<endl;
  report<<yield_total<<endl;

  report<<"$OBS_yield_fleet"<<endl;
  report<<OBS_yield_fleet<<endl;
  report<<"$OBS_yield_region"<<endl;
  report<<OBS_yield_region<<endl;
  report<<"$OBS_yield_population"<<endl;
  report<<OBS_yield_population<<endl;
  report<<"$OBS_yield_total"<<endl;
  report<<OBS_yield_total<<endl;

  report<<"$true_survey_fleet_bio"<<endl;
  report<<true_survey_fleet_bio<<endl;
  report<<"$true_survey_region_bio"<<endl;
  report<<true_survey_region_bio<<endl;
  report<<"$true_survey_population_bio"<<endl;
  report<<true_survey_population_bio<<endl;
  report<<"$true_survey_total_bio"<<endl;
  report<<true_survey_total_bio<<endl;

  report<<"$OBS_survey_fleet_bio"<<endl;
  report<<OBS_survey_fleet_bio<<endl;
  report<<"$OBS_survey_region_bio"<<endl;
  report<<OBS_survey_region_bio<<endl;
  report<<"$OBS_survey_population_bio"<<endl;
  report<<OBS_survey_population_bio<<endl;
  report<<"$OBS_survey_total_bio"<<endl;
  report<<OBS_survey_total_bio<<endl;

  report<<"$true_survey_fleet_bio_overlap"<<endl;
  report<<true_survey_fleet_bio_overlap<<endl;
  report<<"$true_survey_region_bio_overlap"<<endl;
  report<<true_survey_region_bio_overlap<<endl;
  report<<"$true_survey_population_bio_overlap"<<endl;
  report<<true_survey_population_bio_overlap<<endl;
  report<<"$true_survey_natal_bio_overlap"<<endl;
  report<<true_survey_natal_bio_overlap<<endl;
  report<<"$true_survey_total_bio_overlap"<<endl;
  report<<true_survey_total_bio_overlap<<endl;

  report<<"$OBS_survey_fleet_bio_overlap"<<endl;
  report<<OBS_survey_fleet_bio_overlap<<endl;
  report<<"$OBS_survey_region_bio_overlap"<<endl;
  report<<OBS_survey_region_bio_overlap<<endl;
  report<<"$OBS_survey_population_bio_overlap"<<endl;
  report<<OBS_survey_population_bio_overlap<<endl;
  report<<"$OBS_survey_natal_bio_overlap"<<endl;
  report<<OBS_survey_natal_bio_overlap<<endl;
  report<<"$OBS_survey_total_bio_overlap"<<endl;
  report<<OBS_survey_total_bio_overlap<<endl;

  report<<"$harvest_rate_region_bio"<<endl;
  report<<harvest_rate_region_bio<<endl;
  report<<"$harvest_rate_population_bio"<<endl;
  report<<harvest_rate_population_bio<<endl;
  report<<"$harvest_rate_total_bio"<<endl;
  report<<harvest_rate_total_bio<<endl;

  report<<"$depletion_region"<<endl;
  report<<depletion_region<<endl;
  report<<"$depletion_population"<<endl;
  report<<depletion_population<<endl;
  report<<"$depletion_total"<<endl;
  report<<depletion_total<<endl;

  report<<"$SSB_region"<<endl;
  report<<SSB_region<<endl;
  report<<"$SSB_population"<<endl;
  report<<SSB_population<<endl;
  report<<"$SSB_total"<<endl;
  report<<SSB_total<<endl;

  report<<"$SSB_region_overlap"<<endl;
  report<<SSB_region_overlap<<endl;
  report<<"$SSB_population_overlap"<<endl;
  report<<SSB_population_overlap<<endl;
  report<<"$SSB_natal_overlap"<<endl;
  report<<SSB_natal_overlap<<endl;

  report<<"$yield_region_fleet_overlap"<<endl;
  report<<yield_region_fleet_overlap<<endl;
  report<<"$yield_region_overlap"<<endl;
  report<<yield_region_overlap<<endl;
  report<<"$yield_population_overlap"<<endl;
  report<<yield_population_overlap<<endl;
  report<<"$yield_natal_overlap"<<endl;
  report<<yield_natal_overlap<<endl;

  report<<"$OBS_yield_region_fleet_overlap"<<endl;
  report<<OBS_yield_region_fleet_overlap<<endl;
  report<<"$OBS_yield_region_overlap"<<endl;
  report<<OBS_yield_region_overlap<<endl;
  report<<"$OBS_yield_population_overlap"<<endl;
  report<<OBS_yield_population_overlap<<endl;
  report<<"$OBS_yield_natal_overlap"<<endl;
  report<<OBS_yield_natal_overlap<<endl;
  report<<"$OBS_yield_total_overlap"<<endl;
  report<<OBS_yield_total_overlap<<endl;

  report<<"$biomass_AM_overlap_region"<<endl;
  report<<biomass_AM_overlap_region<<endl;
  report<<"$biomass_population_overlap"<<endl;
  report<<biomass_population_overlap<<endl;
  report<<"$biomass_natal_overlap"<<endl;
  report<<biomass_natal_overlap<<endl;

  report<<"$harvest_rate_region_bio_overlap"<<endl;
  report<<harvest_rate_region_bio_overlap<<endl;
  report<<"$harvest_rate_population_bio_overlap"<<endl;
  report<<harvest_rate_population_bio_overlap<<endl;
  report<<"$harvest_rate_natal_bio_overlap"<<endl;
  report<<harvest_rate_natal_bio_overlap<<endl;

  report<<"$depletion_region_overlap"<<endl;
  report<<depletion_region_overlap<<endl;
  report<<"$depletion_population_overlap"<<endl;
  report<<depletion_population_overlap<<endl;
  report<<"$depletion_natal_overlap"<<endl;
  report<<depletion_natal_overlap<<endl;

  report<<"$Bratio_population"<<endl;
  report<<Bratio_population<<endl;
  report<<"$Bratio_total"<<endl;
  report<<Bratio_total<<endl;

  report<<"$Bratio_population_overlap"<<endl;
  report<<Bratio_population_overlap<<endl;
  report<<"$Bratio_natal_overlap"<<endl;
  report<<Bratio_natal_overlap<<endl;


  
RUNTIME_SECTION
  convergence_criteria .001,.0001, 1.0e-4, 1.0e-7
  maximum_function_evaluations 100000
  


