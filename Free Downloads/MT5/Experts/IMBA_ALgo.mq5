//+------------------------------------------------------------------+
//|                                                    IMBA Algo.mq5 |
//|                                        Copyright 2024, AlgoTrade |
//|                                         https://algotrade.co.za/ |
//|                                                                  |
//|                                            Author: M. Oberholzer |
//|                                 E-mail: may.oberholzer@gmail.com |
//+------------------------------------------------------------------+

#property copyright "Copyright 2024, AlgoTrade."
#property link "https://algotrade.co.za"
#property version "1.9"

#property description "IMBA Algo"
#property description " - Author: M. Oberholzer"
#property description " - E-mail: may.oberholzer@gmail.com"

#property icon "MyIcon.ico"
#property strict

#include <Trade/Trade.mqh>
CTrade          Trade;
CPositionInfo   PositionInfo;
#include <Trade/SymbolInfo.mqh>
CSymbolInfo     SymbolInfo;

string AppVersion = "1.9";

enum ENUM_RISK_TYPE
{
   RISK_TYPE_BALANCE_PERCENT = 0,   // Risk based on account balance
   RISK_TYPE_EQUITY_PERCENT = 1,    // Risk based on account equity
   RISK_TYPE_FIXED_LOTS = 2,        // Risk based on fixed lot size
};

input string            sepGeneral = "---- General ----";         // General settings section
input int               InpMagic = 55555;                         // Magic Number
input string            InpTradeComment = "IMBA_";                // Trade Comment
input ENUM_TIMEFRAMES   InpTimeFrame = PERIOD_CURRENT;            // Trading Timeframe

input string            sepIMBA = "---- IMBA settings ----";      // IMBA Settings section
input double            InpIMBAsensitivity = 18;                  // IBMA Sesitivity
input bool              InpShowAlerts = true;                     // Show Alerts
input bool              InpUseTVIMBACalculations = true;          // Use TrdingView IMBA calculations
input bool              InpShowIMBATrendLine = true;              // Show IMBA trend-line
input bool              InpShowSignalLines = false;               // Show signal lines
input bool              InpShowRanges = true;                     // Show Ranges

input string            sepRisk = "---- Risk Setup ----";          // Risk Setup section
input ENUM_RISK_TYPE    InpRiskType = RISK_TYPE_BALANCE_PERCENT;   // Risk Type
input double            InpRisk = 1;                               // Risk Percentage per trade
input double            InpVolume = 0.01;                          // Lotsize for fixed lotsize

input string            sepTrading = "---- Trading Setup ----";    // Trading Setup section
input bool              InpSLFixed = true;                         // SL Fixed
input double            InpSLPercentage = 1;                       // SL Percentage
input double            InpTp1RR = 1;                              // TP1 Risk to Reward                  
input double            InpTp1Percentage = 25;                     // TP1 Percentage
input double            InpTp2RR = 2;                              // TP2 Risk to Reward
input double            InpTp2Percentage = 25;                     // TP2 Percentage
input double            InpTp3RR = 3;                              // TP3 Risk to Reward
input double            InpTp3Percentage = 25;                     // TP3 Percentage
input double            InpTp4RR = 4;                              // TP4 Risk to Reward
input double            InpTp4Percentage = 25;                     // TP4 Percentage
input bool              InpMoveSLtoBE = true;                      // Move SL to BE
input double            InpMoveSLtoBEAfter = 1;                    // Move SL to BE after RR reached
input bool              InpCloseOpositePositionsOnFlip = true;     // Close all trades on new signal or trend change

string preFix = "IMBA_";
int NumberOfDays = 50;

#define UpArrow      233
#define DownArrow    234
#define ArrowShift   15

int      IMBA_Handle;

double   BufferResistance[];
double   BufferSupport[];
double   BufferSell[];
double   BufferBuy[];
double   BufferRangeUpper[];
double   BufferRangeLower[];
double   BufferFib236[];
double   BufferFib786[];
datetime BufferTime[];

int sensitivity = MathRound(InpIMBAsensitivity*10);

bool initDone;
bool debugging = false;

bool commentHidden = false;
bool rangesHidden = false;

bool hadBuySignal = false;
bool hadSellSignal = false;

int EntryIndexLine = 0;
int LastSignalIndex = 0;
double LastSignalEntryPrice = 0;
double LastSignalSLPrice = 0;
double LastSignalRiskInPrice = 0;
double LastSignalTP1Price = 0;
double LastSignalTP2Price = 0;
double LastSignalTP3Price = 0;
double LastSignalTP4Price = 0;

int TradeIndex = 0;

double Ask;
double Bid;
double midPrice;

int hist = 5000;


/*
   CHANGE LOG
   ==========
   
   Ver 1.3
   
   Remove IMBA indicator 
   Calculate values in EA itself
   
   ver 1.4
   
   Fixed digits
   
   ver 1.5
   
   Added function to check enough funds before sending off a trade
   
   ver 1.6
   
   Added fail safe in case lotsize min = 0.01 and risk is more than risk allowed
   Max dd = risk else close all trades
   
   ver 1.7
   
   Included spread and grace to moveSLtoBE function
   
   ver 1.8
   
   Def parameters set
   
   ver 1.9
   
   ...
   
*/


/*
    STRATEGY
    ========

    - Indicator to consume -  IMBA
      -  Sensitivity = How many candles to look back for range (*10 as per TradingView code)
      -  Range top is the highest over that period
      -  Range low is the lowes over that period
    - Use Fib levels to determine trend
      -  0.236, 0.382, 0.5 (Mean), 0.618, 0.786
      -  When Close above 0.5 (Mean) and above 0.236 Buy
      -  When Close below 0.5 (Mean) and below 0.786 Sell
    - Buffers:
      -  0 BufferResistance   (0 or Price)
      -  1 BufferSupport      (0 or price)
      -  2 BufferSell         (0 or price)
      -  3 BufferBuy          (0 or price)
      -  4 BufferRangeUpper   (0 or price)
      -  5 BufferRangeLower   (0 or price)
      -  6 BufferFib236       (0 or price)
      -  7 BufferFib786       (0 or price)

*/                       

void Print_(string str)
{
   if (!debugging)
      return;
   
   Print_(str);
}

void UpdateGUIOutputs()
{

   string calcMode = "TradingView IMBA";
   
   if (!InpUseTVIMBACalculations)
      calcMode = "Industry standard";
      
   double slInPoints = LastSignalRiskInPrice; //Difference in price
   
   slInPoints = slInPoints * MathPow(10,Digits());
   
   double totalRisk = 0;
   string Risktype = "";
   
   if (InpRiskType == RISK_TYPE_BALANCE_PERCENT)
   {
      Risktype = InpRisk + " % of account balance";
      totalRisk = CalculateUnitSize(Symbol(),AccountInfoDouble(ACCOUNT_BALANCE),InpRisk,slInPoints,SymbolInfoDouble( Symbol(), SYMBOL_VOLUME_MAX));
   }   
   else if (InpRiskType == RISK_TYPE_EQUITY_PERCENT)
   {
      Risktype = InpRisk + " % of account equity";
      totalRisk = CalculateUnitSize(Symbol(),AccountInfoDouble(ACCOUNT_EQUITY),InpRisk,slInPoints,SymbolInfoDouble( Symbol(), SYMBOL_VOLUME_MAX));
   }
   else if (InpRiskType == RISK_TYPE_FIXED_LOTS)
   {
      Risktype = "Fixed lot size of " + InpVolume;
      totalRisk = InpVolume;
   }
         
   if(commentHidden)
   {
      Comment("");
   }
   else
   {
      Comment(
       "App Name: " + "IMBA Algo" + " ver. " + AppVersion + "\n",       
       "Account balance: " + TruncateNumber(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "\n",
       "Account equity: " + TruncateNumber(AccountInfoDouble(ACCOUNT_EQUITY), 2) + "\n",
       "Account leverage: " + AccountInfoInteger(ACCOUNT_LEVERAGE) + "\n",
       "Sensitivity: " + InpIMBAsensitivity + "\n"
       "Calculation Mode: " + calcMode + "\n"
       //"Timeframe: " + InpTimeFrame + "\n"       
       //"Digits: " + Digits() + "\n"
       //"Point: " + Point() + "\n"
       //"sl in points: " + LastSignalRiskInPrice * MathPow(10,Digits()) + "\n"
       //"Lot size (Risk type1): " + GetVolume(InpRisk) + "\n"
       //"Lot size (Risk type2): " + GetLotSize(LastSignalEntryPrice,LastSignalSLPrice) + "\n"
       //"Lot size (Risk type3): " + CalculateUnitSize(Symbol(),AccountInfoDouble(ACCOUNT_BALANCE),InpRisk,LastSignalRiskInPrice,SymbolInfoDouble( Symbol(), SYMBOL_VOLUME_MAX)) + "\n"
       //"Lot size (Risk type): " + totalRisk + "\n"
       //"Lot size (Risk type1-1 000): " + GetVolume(InpRisk, 1000) + "\n"
       //"Lot size (Risk type2-1 000): " + GetLotSize(LastSignalEntryPrice,LastSignalSLPrice,1000) + "\n"
       //"Lot size (Risk type3-1 000): " + CalculateUnitSize(Symbol(),1000,InpRisk,LastSignalRiskInPrice,SymbolInfoDouble( Symbol(), SYMBOL_VOLUME_MAX)) + "\n"
       // "Lot size (Risk type3-1 000): " + CalculateUnitSize(Symbol(),1000,InpRisk,slInPoints,SymbolInfoDouble( Symbol(), SYMBOL_VOLUME_MAX)) + "\n"
       //"Lot size (Risk type1-10 000): " + GetVolume(InpRisk, 10000) + "\n"
       //"Lot size (Risk type2-10 000): " + GetLotSize(LastSignalEntryPrice,LastSignalSLPrice,10000) + "\n"
       //"Lot size (Risk type3-10 000): " + CalculateUnitSize(Symbol(),10000,InpRisk,LastSignalRiskInPrice,SymbolInfoDouble( Symbol(), SYMBOL_VOLUME_MAX)) + "\n"
       //"Lot size (Risk type3-10 000): " + CalculateUnitSize(Symbol(),10000,InpRisk,slInPoints,SymbolInfoDouble( Symbol(), SYMBOL_VOLUME_MAX)) + "\n"
       //"Lot size (Risk type1-100 000): " + GetVolume(InpRisk, 100000) + "\n"
       //"Lot size (Risk type2-100 000): " + GetLotSize(LastSignalEntryPrice,LastSignalSLPrice,100000) + "\n"
       //"Lot size (Risk type3-100 000): " + CalculateUnitSize(Symbol(),100000,InpRisk,LastSignalRiskInPrice,SymbolInfoDouble( Symbol(), SYMBOL_VOLUME_MAX)) + "\n"
       //"Current trade setup risk in price: " + NormalizeDouble(LastSignalRiskInPrice, Digits()) + "\n"
       "Risk type: " + Risktype + "\n"       
       //"Lot size based on current risk settings: " + totalRisk + "\n"              
       //"Lot size (Risk type3-100 000): " + CalculateUnitSize(Symbol(),100000,InpRisk,slInPoints,SymbolInfoDouble( Symbol(), SYMBOL_VOLUME_MAX)) + "\n"       
       "TP1: RR " + InpTp1RR + " - TP1 % of risk " + InpTp1Percentage + " % = lot size of " + NormalizeLots(Symbol(),totalRisk*InpTp1Percentage/100) + "\n"
       "TP2: RR " + InpTp2RR + " - TP2 % of risk " + InpTp2Percentage + " % = lot size of " + NormalizeLots(Symbol(),totalRisk*InpTp2Percentage/100) + "\n"
       "TP3: RR " + InpTp3RR + " - TP3 % of risk " + InpTp3Percentage + " % = lot size of " + NormalizeLots(Symbol(),totalRisk*InpTp3Percentage/100) + "\n"
       "TP4: RR " + InpTp4RR + " - TP4 % of risk " + InpTp4Percentage + " % = lot size of " + NormalizeLots(Symbol(),totalRisk*InpTp4Percentage/100) + "\n"
       //"Lot size based on an account balance of 100: " + CalculateUnitSize(Symbol(),100,InpRisk,slInPoints,SymbolInfoDouble( Symbol(), SYMBOL_VOLUME_MAX)) + "\n"
       //"Lot size based on an account balance of 1000: " + CalculateUnitSize(Symbol(),1000,InpRisk,slInPoints,SymbolInfoDouble( Symbol(), SYMBOL_VOLUME_MAX)) + "\n"
       //"Lot size based on an account balance of 10000: " + CalculateUnitSize(Symbol(),10000,InpRisk,slInPoints,SymbolInfoDouble( Symbol(), SYMBOL_VOLUME_MAX)) + "\n"
       //"Lot size based on an account balance of 100000: " + CalculateUnitSize(Symbol(),100000,InpRisk,slInPoints,SymbolInfoDouble( Symbol(), SYMBOL_VOLUME_MAX)) + "\n"
       "SL fixed: " + InpSLFixed + "\n"
       "SL %: " + InpSLPercentage + "\n"
       "Close positions on trend change: " + InpCloseOpositePositionsOnFlip + "\n"       
       );
   }
}

bool IsNewBar(ENUM_TIMEFRAMES tf)
{
    static datetime previousTime = 0;
    datetime currentTime = iTime(Symbol(),tf,0);

    if(previousTime == currentTime) return false;

    previousTime = currentTime;

    return true;
}

void ResizeArrays()
{
   Print_("Resizing arrays");
   ArrayResize(BufferResistance, index + 1, index + 1);
   ArrayResize(BufferSupport, index + 1, index + 1);
   ArrayResize(BufferSell, index + 1, index + 1);
   ArrayResize(BufferBuy, index + 1, index + 1);
   ArrayResize(BufferRangeUpper, index + 1, index + 1);
   ArrayResize(BufferRangeLower, index + 1, index + 1);
   ArrayResize(BufferFib236, index + 1, index + 1);
   ArrayResize(BufferFib786, index + 1, index + 1);
   ArrayResize(BufferTime, index + 1, index + 1);
}

int index = 0;

int OnInit()
{
   Print("EA: OnInit");

   Print("EA: OnInit - Initializing....");

   Print("EA: OnInit - Deleting all objects....");
   ObjectsDeleteAllEAObjects();
   
   GetVolumeEquityPercent();
   
   // Clear arrays
   ArrayFree(BufferResistance);
   ArrayFree(BufferSupport);
   ArrayFree(BufferSell);
   ArrayFree(BufferBuy);
   ArrayFree(BufferRangeUpper);
   ArrayFree(BufferRangeLower);
   ArrayFree(BufferFib236);
   ArrayFree(BufferFib786);
   ArrayFree(BufferTime);
   
   Trade.SetExpertMagicNumber(InpMagic);
   
   indexAfter = hist+1;
   
   if (index == 0)
   {
      index = hist;
      ResizeArrays();
      
      BufferResistance[0] = 0;
      BufferSupport[0] = 0;
      BufferSell[0] = 0;
      BufferBuy[0] = 0;
      BufferRangeUpper[0] = 0;
      BufferRangeLower[0] = 0;
      BufferFib236[0] = 0;
      BufferFib786[0] = 0;
      BufferTime[0] = iTime(Symbol(), Period(), hist + 1);
   }

   CreateButtons();
   
   OnTick();
   
   initDone = true;

   Print("EA: OnInit - Done!....");
   
   return (INIT_SUCCEEDED);
}

void CreateButtons()
{

    Print_("Creating buttons...");
    string btnName =  preFix +"btnShowHideComments";
    
    ObjectCreate        (0, btnName, OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger    (0, btnName, OBJPROP_XSIZE, 23); 
    ObjectSetInteger    (0, btnName, OBJPROP_YSIZE, 18);
    ObjectSetString     (0, btnName, OBJPROP_TEXT, "<<");
    ObjectSetString     (0, btnName, OBJPROP_FONT, "Arial"); 
    ObjectSetInteger    (0, btnName, OBJPROP_FONTSIZE, 8); 
    ObjectSetInteger    (0, btnName, OBJPROP_ALIGN, ALIGN_CENTER);
    ObjectSetInteger    (0, btnName, OBJPROP_COLOR, clrBlack); //Text color
    ObjectSetInteger    (0, btnName, OBJPROP_BGCOLOR, C'236,233,216');
    ObjectSetInteger    (0, btnName, OBJPROP_BORDER_COLOR, clrNONE);
    ////ObjectSetInteger    (0, btnName, OBJPROP_BACK, false);
    ObjectSetInteger    (0, btnName, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
    ObjectSetInteger    (0, btnName, OBJPROP_XDISTANCE, 30);
    ObjectSetInteger    (0, btnName, OBJPROP_YDISTANCE, 20);     
    ObjectSetInteger    (0, btnName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger    (0, btnName, OBJPROP_SELECTED, false);
    ObjectSetInteger    (0, btnName, OBJPROP_HIDDEN, false);   
    ObjectSetInteger    (0, btnName, OBJPROP_ZORDER, 1);
    ObjectSetString     (0, btnName, OBJPROP_TOOLTIP, "Hide comments section");

    //ObjectCreate        (0, btnName, OBJ_EDIT, 0, 0, 0);
    //ObjectSetInteger    (0, btnName, OBJPROP_XDISTANCE, 150);
    //ObjectSetInteger    (0, btnName, OBJPROP_YDISTANCE, 50);
    //ObjectSetInteger    (0, btnName, OBJPROP_XSIZE, 50); 
    //ObjectSetInteger    (0, btnName, OBJPROP_YSIZE, 18);
    //ObjectSetString     (0, btnName, OBJPROP_TEXT, "<<");
    //ObjectSetString     (0, btnName, OBJPROP_FONT, "Arial"); 
    //ObjectSetInteger    (0, btnName, OBJPROP_FONTSIZE, 10); 
    //ObjectSetInteger    (0, btnName, OBJPROP_ALIGN, ALIGN_CENTER);
    ////ObjectSetInteger    (0, btnName, OBJPROP_READONLY, true); 
    //ObjectSetInteger    (0, btnName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    //ObjectSetInteger    (0, btnName, OBJPROP_COLOR, clrAqua);
    ////ObjectSetInteger    (0, btnName, OBJPROP_BGCOLOR, clrBlack);
    ////ObjectSetInteger    (0, btnName, OBJPROP_BORDER_COLOR, clrBlack);
    ////ObjectSetInteger    (0, btnName, OBJPROP_BACK, false);
    ////ObjectSetInteger    (0, btnName, OBJPROP_ZORDER, 1);
    ////ObjectSetInteger    (0, btnName, OBJPROP_SELECTABLE, false);
    ////ObjectSetInteger    (0, btnName, OBJPROP_SELECTED, false);
    ////ObjectSetInteger    (0, btnName, OBJPROP_HIDDEN, false);
    ////ObjectSetInteger    (0, btnName, OBJPROP_READONLY, true);   
    
    if(InpShowRanges)
    {
       btnName =  preFix+"btnShowHideLevels";
       
       ObjectCreate        (0, btnName, OBJ_BUTTON, 0, 0, 0);
       ObjectSetInteger    (0, btnName, OBJPROP_XSIZE, 23); 
       ObjectSetInteger    (0, btnName, OBJPROP_YSIZE, 18);
       ObjectSetString     (0, btnName, OBJPROP_TEXT, "<<");
       ObjectSetString     (0, btnName, OBJPROP_FONT, "Arial"); 
       ObjectSetInteger    (0, btnName, OBJPROP_FONTSIZE, 8); 
       ObjectSetInteger    (0, btnName, OBJPROP_ALIGN, ALIGN_CENTER);
       ObjectSetInteger    (0, btnName, OBJPROP_COLOR, clrBlack); //Text color
       ObjectSetInteger    (0, btnName, OBJPROP_BGCOLOR, C'236,233,216');
       ObjectSetInteger    (0, btnName, OBJPROP_BORDER_COLOR, clrNONE);
       ////ObjectSetInteger    (0, btnName, OBJPROP_BACK, false);
       ObjectSetInteger    (0, btnName, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
       ObjectSetInteger    (0, btnName, OBJPROP_XDISTANCE, 30);
       ObjectSetInteger    (0, btnName, OBJPROP_YDISTANCE, 40);     
       ObjectSetInteger    (0, btnName, OBJPROP_SELECTABLE, false);
       ObjectSetInteger    (0, btnName, OBJPROP_SELECTED, false);
       ObjectSetInteger    (0, btnName, OBJPROP_HIDDEN, false);   
       ObjectSetInteger    (0, btnName, OBJPROP_ZORDER, 1);
       ObjectSetString     (0, btnName, OBJPROP_TOOLTIP, "Hide ranges");
   }

}

void OnChartEvent(const int id,  const long  & lparam, const double  & dparam, const string  & sparam)
{     
    if (sparam ==  preFix+"btnShowHideComments")
    { 
       Print_(preFix+"btnShowHideComments...");
       commentHidden = !commentHidden;
       if(commentHidden)
       {
         ObjectSetString     (0, preFix+"btnShowHideComments", OBJPROP_TEXT, ">>");
         ObjectSetString     (0, preFix+"btnShowHideComments", OBJPROP_TOOLTIP, "Show comments section");
         UpdateGUIOutputs();
       }
       else
       {
         ObjectSetString     (0, preFix+"btnShowHideComments", OBJPROP_TEXT, "<<");
         ObjectSetString     (0, preFix+"btnShowHideComments", OBJPROP_TOOLTIP, "Hide comments section");
         UpdateGUIOutputs();
       }
    }
    
    if (sparam ==  preFix+"btnShowHideLevels")
    { 
       Print_(preFix+"btnShowHideLevels...");
       rangesHidden = !rangesHidden;
       if(rangesHidden)
       {
         ObjectSetString     (0, preFix+"btnShowHideLevels", OBJPROP_TEXT, ">>");
         ObjectSetString     (0, preFix+"btnShowHideLevels", OBJPROP_TOOLTIP, "Show ranges");
         HideObjects("Range");
         HideObjects("Fib50");
         HideObjects("Fib236");
         HideObjects("Fib786");
         UpdateGUIOutputs();
       }
       else
       {
         ObjectSetString     (0, preFix+"btnShowHideLevels", OBJPROP_TEXT, "<<");
         ObjectSetString     (0, preFix+"btnShowHideLevels", OBJPROP_TOOLTIP, "Hide ranges");
         ShowObjects("Range");
         ShowObjects("Fib50");
         ShowObjects("Fib236");
         ShowObjects("Fib786");
         UpdateGUIOutputs();
       }
    }
}

void OnDeinit(const int reason)
{

   Print("EA: OnDeInit");
          
   initDone = false;
   hadBuySignal = false;
   hadSellSignal = false;
   index = 0;
    
   ObjectsDeleteAllEAObjects();

   return;
}

void ObjectsDeleteAllEAObjects()
{
   if(!MQLInfoInteger(MQL_TESTER))
   {  
      //ObjectsDeleteAll(0);
      
      Comment("");
      for (int i = ObjectsTotal(0) - 1; i >= 0; i--)
      {
         string str = ObjectName(0, i);
   
         if(StringFind(str, preFix, 0) == -1)
            continue;
   
         ObjectDelete(0, str);
      }
   }
}

void Alert_(string str)
{
   if(!InpShowAlerts)
      return; 
   
   Alert(str);
}

void OnTick()
{

   //ObjectDelete(0, "Trend0");
   
   bool isNewBar = IsNewBar(InpTimeFrame);
   
   Ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   Bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   midPrice = Ask - ((Ask - Bid) / 2);
   
   if(isNewBar || !initDone)
   {
      Print_("New bar!");
      
      datetime time = iTime(Symbol(), InpTimeFrame, 0);
      
      if(!hadBuySignal && !hadSellSignal)
      {
         //INIT
         GetIMBAvalues(hist);
                  
         for(int i=1;i<hist-1;i++)
         {
            if(BufferBuy[i] != 0)
            {
               hadBuySignal = true;
               Print_("Last BuySignal found at index: " + i);
               
               DoBuy(i);             
               
               break;
            }
            else if(BufferSell[i] != 0)
            {
               hadSellSignal = true;
               Print_("Last SellSignal found at index: " + i);
               
               DoSell(i);      
               
               break;
            }
         }
      }
      else
      {
         LastSignalIndex++;
      }
      
      if(initDone)
         GetIMBAvalues();     
      
      if(BufferBuy[1] !=0 || (hadSellSignal && BufferSupport[1] != 0))
      {
         if(InpCloseOpositePositionsOnFlip)
            CloseAll();
            
         Print_Values();
      
         hadBuySignal = true;
         hadSellSignal = false;
         
         Print_(Symbol() + " " + "IMBA Algo " + "Buy signal received at: " + time);
         Alert_(Symbol() + " " + "IMBA Algo " + "Buy signal received at: " + time);
         
         DoBuy(1);
                 
         if(InpTp1RR != 0 && InpTp1Percentage != 0)
            OpenTrade(ORDER_TYPE_BUY, LastSignalSLPrice, LastSignalTP1Price, GetVolume(InpTp1Percentage), InpTradeComment + "+_T1_" + TradeIndex++);
         if(InpTp2RR != 0 && InpTp2Percentage != 0)
            OpenTrade(ORDER_TYPE_BUY, LastSignalSLPrice, LastSignalTP2Price, GetVolume(InpTp2Percentage), InpTradeComment + "+_T2_" + TradeIndex++);
         if(InpTp3RR != 0 && InpTp3Percentage != 0)
            OpenTrade(ORDER_TYPE_BUY, LastSignalSLPrice, LastSignalTP3Price, GetVolume(InpTp3Percentage), InpTradeComment + "+_T3_" + TradeIndex++);
         if(InpTp4RR != 0 && InpTp4Percentage != 0)
            OpenTrade(ORDER_TYPE_BUY, LastSignalSLPrice, LastSignalTP4Price, GetVolume(InpTp4Percentage), InpTradeComment + "+_T4_" + TradeIndex++);
               
      }
      else if (BufferSell[1] != 0 || (hadBuySignal && BufferResistance[1] != 0))
      {
         if(InpCloseOpositePositionsOnFlip)
            CloseAll();
            
         Print_Values();
         
         hadBuySignal = false;
         hadSellSignal = true;
         
         Print_(Symbol() + " " + "IMBA Algo " + "Sell signal received at: " + time);
         Alert_(Symbol() + " " + "IMBA Algo " + "Sell signal received at: " + time);
         
         DoSell(1);
                  
         if(InpTp1RR != 0 && InpTp1Percentage != 0)
            OpenTrade(ORDER_TYPE_SELL, LastSignalSLPrice, LastSignalTP1Price, GetVolume(InpTp1Percentage), InpTradeComment + "_T1_" + TradeIndex++);
         if(InpTp2RR != 0 && InpTp2Percentage != 0)
            OpenTrade(ORDER_TYPE_SELL, LastSignalSLPrice, LastSignalTP2Price, GetVolume(InpTp2Percentage), InpTradeComment + "_T2_" + TradeIndex++);
         if(InpTp3RR != 0 && InpTp3Percentage != 0)
            OpenTrade(ORDER_TYPE_SELL, LastSignalSLPrice, LastSignalTP3Price, GetVolume(InpTp3Percentage), InpTradeComment + "_T3_" + TradeIndex++);
         if(InpTp4RR != 0 && InpTp4Percentage != 0)
            OpenTrade(ORDER_TYPE_SELL, LastSignalSLPrice, LastSignalTP4Price, GetVolume(InpTp4Percentage), InpTradeComment + "_T4_" + TradeIndex++);            
      }
      else
      {
         //Update drawings
         UpdateLastPositionInfo(0);        
      }
   }
   
   ManageTrades();
   
   if(!MQLInfoInteger(MQL_TESTER))
      UpdateGUIOutputs();   
}

bool closeTradesIfRiskExceeded = false;
void ManageTrades()
{
   // close all if dd > risk
   double profit = 0;

   // Do we have some open trades - else there is nothing to manage...
   if(PositionsTotal() > 0)
   {
      //This is for MQL5 Community check
      if(closeTradesIfRiskExceeded)
      {
         for(int i = PositionsTotal() -1; i >= 0; i--)
         {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0)
            {
               continue;
            }
      
            if(PositionInfo.Symbol() == Symbol() && PositionInfo.Magic() == InpMagic)
            {
            
               profit += PositionInfo.Profit();            
            }
         }
         
         if(profit <= -(silentRiskStopCheck))
         {
            Print("Max DD reached of 1% - closing all trades");
            CloseAll();
         }   
      }
   
      if(
            InpMoveSLtoBE && 
               (
                 (hadBuySignal && Ask > (LastSignalEntryPrice + (LastSignalRiskInPrice * InpMoveSLtoBEAfter ))) ||
                 (hadSellSignal && Bid < (LastSignalEntryPrice - (LastSignalRiskInPrice * InpMoveSLtoBEAfter )))
               )                              
         )
      {
         Print_("MoveToBE...");
         MoveToBE("", false);
      }
   }   
}

void CloseAll ()
{
   //Print_("Closing all positions for: " + Symbol() + " with magic no: " + InpMagic);
   
    for(int i = PositionsTotal() -1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0)
        {
            continue;
        }
        if(PositionInfo.Symbol() == Symbol() && PositionInfo.Magic() == InpMagic)
        {
            //Print_("Closing...");
            Trade.PositionClose(ticket);
            //Print_("Closed!");
        }
    }
}

void MoveToBE (string comment, bool includeSpread)
{
   for(int i = PositionsTotal() -1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
      {
         continue;
      }

      if(comment != "")
      {
         if(StringFind(PositionInfo.Comment(), comment, 0) == -1)
         {
            continue;
         }         
      }

      if(PositionInfo.Symbol() == Symbol() && PositionInfo.Magic() == InpMagic)
      {
         double spread = 0;

         if (includeSpread)
         {
            spread = SymbolInfo.Spread();
         }
         
         // Add grace to spread
         //double pips = SymbolInfoDouble(Symbol(), );
         //spread = PipsToPrice(spread+pips);

         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && Bid > (PositionInfo.PriceOpen() + spread) && PositionInfo.StopLoss() < (PositionInfo.PriceOpen() - spread))
         {
            Trade.PositionModify(ticket, PositionInfo.PriceOpen() + spread, PositionInfo.TakeProfit());
         }               
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && Ask < (PositionInfo.PriceOpen() - spread) && PositionInfo.StopLoss() > (PositionInfo.PriceOpen() + spread))
         {
            Trade.PositionModify(ticket, PositionInfo.PriceOpen() - spread, PositionInfo.TakeProfit());
         }         
      }
   }
}

double PipsToPrice(double pips)
{
    return (pips * PipSize(Symbol()));
}

double PipSize(string symbol)
{
	double point = SymbolInfoDouble(symbol,SYMBOL_POINT);
	int digits = (int) SymbolInfoInteger(symbol, SYMBOL_DIGITS);
	return (((digits % 2) == 1) ? point * 10 : point);
}

void Print_Values()
{
   Print_("BufferResistance[0]="+BufferResistance[0]);
   Print_("BufferSupport[0]="+BufferSupport[0]);
   Print_("BufferRangeUpper[0]="+BufferRangeUpper[0]);
   Print_("BufferLower[0]="+BufferRangeLower[0]);
   Print_("BufferFib236[0]="+BufferFib236[0]);
   Print_("BufferFib786[0]="+BufferFib786[0]);
   Print_("BufferBuy[0]="+BufferBuy[0]);
   Print_("BufferSell[0]="+BufferSell[0]);
}

double GetVolume(double p)
{
   if(InpRiskType == RISK_TYPE_FIXED_LOTS)
      return NormalizeVolume(InpVolume);
   
   Print_("p="+p);
   Print_("p/100="+(p/100));
   double vol = GetVolumeEquityPercent();
   Print_("vol total per 1% risk = " + vol);
   vol = vol*(p/100);
   Print_("vol="+vol);
   Print_("nor vol="+NormalizeVolume(vol));
   return NormalizeVolume(vol);
}

double GetVolume(double p, double balance)
{
   if(InpRiskType == RISK_TYPE_FIXED_LOTS)
      return NormalizeVolume(InpVolume);
   
   Print_("p="+p);
   Print_("p/100="+(p/100));
   double vol = GetVolumeEquityPercent(balance);
   Print_("vol total per 1% risk = " + vol);
   vol = vol*(p/100);
   Print_("vol="+vol);
   Print_("nor vol="+NormalizeVolume(vol));
   return NormalizeVolume(vol);
}

double NormalizeVolume(double vol)
{
   if (vol <= 0) return 0;
   
   double max = SymbolInfoDouble( Symbol(), SYMBOL_VOLUME_MAX);
   double min = SymbolInfoDouble( Symbol(), SYMBOL_VOLUME_MIN);
   double step = SymbolInfoDouble( Symbol(), SYMBOL_VOLUME_STEP);
   
   double result = MathRound(vol/step)*step;
   
   if (result>max) result = max;
   if (result<min) result = min;
   
   return NormalizeDouble(result,2);
}

double silentRiskStopCheck = 0;

double GetVolumeEquityPercent()
{
   double basedon = AccountInfoDouble(ACCOUNT_BALANCE);
   
   if(InpRiskType == RISK_TYPE_EQUITY_PERCENT)
      basedon = AccountInfoDouble(ACCOUNT_EQUITY);
   
   double riskAmout = basedon * InpRisk/100;
   silentRiskStopCheck = riskAmout;
   
   double sl = LastSignalRiskInPrice; // THis is price difference = 1.07907 - 1.07785 = 0.00122 (Points)
   //if(Digits() == 3 || Digits() == 5) {
   //  sl *= 10;
   //} 
   
   double tickValue = SymbolInfoDouble( Symbol(), SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble( Symbol(), SYMBOL_TRADE_TICK_SIZE);
   double lossTicks = sl/tickSize;
   
   double vol = riskAmout/(lossTicks*tickValue);  
   
   return vol;
}

double GetVolumeEquityPercent(double balance)
{
   double basedon = balance;
   
   if(InpRiskType == RISK_TYPE_EQUITY_PERCENT)
      basedon = AccountInfoDouble(ACCOUNT_EQUITY);
   
   double riskAmout = basedon * InpRisk/100;
   silentRiskStopCheck = riskAmout;
   
   double sl = LastSignalRiskInPrice; // THis is price difference = 1.07907 - 1.07785 = 0.00122 (Points)
   if(Digits() == 3 || Digits() == 5) {
     sl *= 10;
   } 
   
   double tickValue = SymbolInfoDouble( Symbol(), SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble( Symbol(), SYMBOL_TRADE_TICK_SIZE);
   double lossTicks = sl/tickSize;
   
   double vol = riskAmout/(lossTicks*tickValue);  
   
   return vol;
}

double GetLotSize(double entryPrice, double stopLossPrice)
{
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskPercentage = 1.0; // 1% risk
    
    double tickValue = SymbolInfoDouble( Symbol(), SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble( Symbol(), SYMBOL_TRADE_TICK_SIZE);
   
    double pipValue = tickValue / tickSize;
    double pipsToRisk = MathAbs(stopLossPrice - entryPrice) / Point();
    
    double tradeAmount = accountBalance * riskPercentage / 100.0;
    double lotSize = tradeAmount / (pipsToRisk * pipValue);
    
    double max = SymbolInfoDouble( Symbol(), SYMBOL_VOLUME_MAX);
    double min = SymbolInfoDouble( Symbol(), SYMBOL_VOLUME_MIN);
    double step = SymbolInfoDouble( Symbol(), SYMBOL_VOLUME_STEP);
    
    // Round lot size to nearest valid step
    lotSize = MathRound(lotSize / step) * step;
    
    // Ensure lot size is within allowed range
    lotSize = MathMax(min, MathMin(max, lotSize));
    
    return lotSize;
}

double GetLotSize(double entryPrice, double stopLossPrice, double balance)
{
    double accountBalance = balance;
    double riskPercentage = 1.0; // 1% risk
    
    double tickValue = SymbolInfoDouble( Symbol(), SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble( Symbol(), SYMBOL_TRADE_TICK_SIZE);
   
    double pipValue = tickValue / tickSize;
    double pipsToRisk = MathAbs(stopLossPrice - entryPrice) / Point();
    
    double tradeAmount = accountBalance * riskPercentage / 100.0;
    double lotSize = tradeAmount / (pipsToRisk * pipValue);
    
    double max = SymbolInfoDouble( Symbol(), SYMBOL_VOLUME_MAX);
    double min = SymbolInfoDouble( Symbol(), SYMBOL_VOLUME_MIN);
    double step = SymbolInfoDouble( Symbol(), SYMBOL_VOLUME_STEP);
    
    // Round lot size to nearest valid step
    lotSize = MathRound(lotSize / step) * step;
    
    // Ensure lot size is within allowed range
    lotSize = MathMax(min, MathMin(max, lotSize));
    
    return lotSize;
}

//==================================

double CalculateUnitSize(string pMarket, double pMoneyCapital, double pRiskPercentage, int pStoplossPoints, double pAllowedMaxUnitSize) 
   {  
   
      //---Calculate LotSize based on Equity, Risk in decimal and StopLoss in points
      double maxLots, minLots, oneTickValue, moneyRisk, lotsByRisk, lotSize;
      int totalTickCount;

      maxLots = MaxUnitSizeAllowedForMargin(pMarket, pMoneyCapital, pAllowedMaxUnitSize);
      minLots = SymbolInfoDouble(pMarket, SYMBOL_VOLUME_MIN);
      oneTickValue = SymbolInfoDouble(pMarket, SYMBOL_TRADE_TICK_VALUE); // Tick value of the asset

      moneyRisk = (pRiskPercentage/100) * pMoneyCapital;
      totalTickCount = ToTicksCount(pMarket, pStoplossPoints);

      //---Calculate the Lot size according to Risk.
      lotsByRisk = moneyRisk / (totalTickCount * oneTickValue);
      lotSize = MathMax(MathMin(lotsByRisk, maxLots), minLots);      
      lotSize = NormalizeLots(pMarket, lotSize);
      return (lotSize);
   }

   double MaxUnitSizeAllowedForMargin(string pMarket, double pMoneyCapital, double pAllowedMaxUnitSize) 
   {
      // Calculate Lot size according to Equity.
      double marginForOneLot, lotsPossible;
      if(OrderCalcMargin(ORDER_TYPE_BUY, pMarket, 1, SymbolInfoDouble(pMarket, SYMBOL_ASK), marginForOneLot)) { // Calculate margin required for 1 lot
         lotsPossible = pMoneyCapital * 0.98 / marginForOneLot;
         lotsPossible = MathMin(lotsPossible, MathMin(pAllowedMaxUnitSize, SymbolInfoDouble(pMarket, SYMBOL_VOLUME_MAX)));
         lotsPossible = NormalizeLots(pMarket, lotsPossible);
      } else {
         lotsPossible = SymbolInfoDouble(pMarket, SYMBOL_VOLUME_MAX);
      }   
      return (lotsPossible);
   }

   int ToTicksCount(string pMarket, uint pPointsCount) 
   {
      double uticksize = SymbolInfoDouble(pMarket, SYMBOL_TRADE_TICK_SIZE);
      int utickscount = uticksize > 0 ? (int)((pPointsCount / uticksize) * uticksize) : 0; //-- fix prices by ticksize
      return utickscount;
   }

   double NormalizeLots(string pMarket, double pLots) {       
      double lotstep   = SymbolInfoDouble(pMarket, SYMBOL_VOLUME_STEP);
      int lotdigits    = (int) - MathLog10(lotstep);
      return NormalizeDouble(pLots, lotdigits);   
   } 


//==================================

void UpdateLastPositionInfo(int i)
{
   datetime time = iTime(Symbol(), InpTimeFrame, i);
   
   int index = EntryIndexLine-1;
   
   ObjectCreate(0, preFix+"Entry" + index, OBJ_TREND, 0, iTime(Symbol(),InpTimeFrame,LastSignalIndex), LastSignalEntryPrice, time, LastSignalEntryPrice);
   ObjectSetInteger(0, preFix+"Entry" + index, OBJPROP_COLOR, clrYellow);
   ObjectSetInteger(0, preFix+"Entry" + index, OBJPROP_STYLE, STYLE_DOT);
   
   ObjectCreate(0, preFix+"SL" + index, OBJ_TREND, 0, iTime(Symbol(),InpTimeFrame,LastSignalIndex), LastSignalSLPrice, time, LastSignalSLPrice);
   ObjectSetInteger(0, preFix+"SL" + index, OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, preFix+"SL" + index, OBJPROP_STYLE, STYLE_DOT);
   
   ObjectCreate(0, preFix+"TP1" + index, OBJ_TREND, 0, iTime(Symbol(),InpTimeFrame,LastSignalIndex), LastSignalTP1Price, time, LastSignalTP1Price);
   ObjectSetInteger(0, preFix+"TP1" + index, OBJPROP_COLOR, clrGreen);
   ObjectSetInteger(0, preFix+"TP1" + index, OBJPROP_STYLE, STYLE_DOT);
   
   ObjectCreate(0, preFix+"TP2" + index, OBJ_TREND, 0, iTime(Symbol(),InpTimeFrame,LastSignalIndex), LastSignalTP2Price, time, LastSignalTP2Price);
   ObjectSetInteger(0, preFix+"TP2" + index, OBJPROP_COLOR, clrGreen);
   ObjectSetInteger(0, preFix+"TP2" + index, OBJPROP_STYLE, STYLE_DOT);
   
   ObjectCreate(0, preFix+"TP3" + index, OBJ_TREND, 0, iTime(Symbol(),InpTimeFrame,LastSignalIndex), LastSignalTP3Price, time, LastSignalTP3Price);
   ObjectSetInteger(0, preFix+"TP3" + index, OBJPROP_COLOR, clrGreen);
   ObjectSetInteger(0, preFix+"TP3" + index, OBJPROP_STYLE, STYLE_DOT);
   
   ObjectCreate(0, preFix+"TP4" + index, OBJ_TREND, 0, iTime(Symbol(),InpTimeFrame,LastSignalIndex), LastSignalTP4Price, time, LastSignalTP4Price);
   ObjectSetInteger(0, preFix+"TP4" + index, OBJPROP_COLOR, clrGreen);
   ObjectSetInteger(0, preFix+"TP4" + index, OBJPROP_STYLE, STYLE_DOT);
}

void DoBuy(int i)
{
   datetime time = iTime(Symbol(), InpTimeFrame, i);
   double close = iClose(Symbol(), InpTimeFrame, i);
   double open = iOpen(Symbol(), InpTimeFrame, i);
   
   LastSignalIndex = i;
   LastSignalEntryPrice = close; // BufferBuy[i];
   
   if (LastSignalEntryPrice==0)
   {
      LastSignalEntryPrice = close;
   }
   
   ObjectCreate(0, preFix+"Entry" + EntryIndexLine, OBJ_TREND, 0, iTime(Symbol(),InpTimeFrame,LastSignalIndex), LastSignalEntryPrice, time, LastSignalEntryPrice);
   ObjectSetInteger(0, preFix+"Entry" + EntryIndexLine, OBJPROP_COLOR, clrYellow);
   ObjectSetInteger(0, preFix+"Entry" + EntryIndexLine, OBJPROP_STYLE, STYLE_DOT);
      
   if(!InpUseTVIMBACalculations)
   {
      if(InpSLFixed)
      {
         LastSignalSLPrice = BufferSupport[i];         
      }
      else
      {
         LastSignalSLPrice = BufferFib786[i];
      }  
   }
   else
   {
      if(InpSLFixed)
      {
         LastSignalSLPrice = LastSignalEntryPrice * (1 - InpSLPercentage/100);
      }
      else
      {
         LastSignalSLPrice = BufferFib786[i] * (1 - InpSLPercentage/100);
      }  
   }    
     
   ObjectCreate(0, preFix+"SL" + EntryIndexLine, OBJ_TREND, 0, iTime(Symbol(),InpTimeFrame,LastSignalIndex), LastSignalSLPrice, time, LastSignalSLPrice);
   ObjectSetInteger(0, preFix+"SL" + EntryIndexLine, OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, preFix+"SL" + EntryIndexLine, OBJPROP_STYLE, STYLE_DOT);
   
   LastSignalRiskInPrice = LastSignalEntryPrice - LastSignalSLPrice;
   
   if(!InpUseTVIMBACalculations)
   {
      // Most correct - my impementation
      LastSignalTP1Price = LastSignalEntryPrice + LastSignalRiskInPrice * InpTp1RR;
      LastSignalTP2Price = LastSignalEntryPrice + LastSignalRiskInPrice * InpTp2RR;
      LastSignalTP3Price = LastSignalEntryPrice + LastSignalRiskInPrice * InpTp3RR;
      LastSignalTP4Price = LastSignalEntryPrice + LastSignalRiskInPrice * InpTp4RR;
   }
   else
   {      
      //IMBA implementation
      LastSignalTP1Price = LastSignalEntryPrice * (1 + InpTp1RR/100);
      LastSignalTP2Price = LastSignalEntryPrice * (1 + InpTp2RR/100);
      LastSignalTP3Price = LastSignalEntryPrice * (1 + InpTp3RR/100);
      LastSignalTP4Price = LastSignalEntryPrice * (1 + InpTp4RR/100);
   }
   
   ObjectCreate(0, preFix+"TP1" + EntryIndexLine, OBJ_TREND, 0, iTime(Symbol(),InpTimeFrame,LastSignalIndex), LastSignalTP1Price, time, LastSignalTP1Price);
   ObjectSetInteger(0, preFix+"TP1" + EntryIndexLine, OBJPROP_COLOR, clrGreen);
   ObjectSetInteger(0, preFix+"TP1" + EntryIndexLine, OBJPROP_STYLE, STYLE_DOT);
   
   ObjectCreate(0, preFix+"TP2" + EntryIndexLine, OBJ_TREND, 0, iTime(Symbol(),InpTimeFrame,LastSignalIndex), LastSignalTP2Price, time, LastSignalTP2Price);
   ObjectSetInteger(0, preFix+"TP2" + EntryIndexLine, OBJPROP_COLOR, clrGreen);
   ObjectSetInteger(0, preFix+"TP2" + EntryIndexLine, OBJPROP_STYLE, STYLE_DOT);
   
   ObjectCreate(0, preFix+"TP3" + EntryIndexLine, OBJ_TREND, 0, iTime(Symbol(),InpTimeFrame,LastSignalIndex), LastSignalTP3Price, time, LastSignalTP3Price);
   ObjectSetInteger(0, preFix+"TP3" + EntryIndexLine, OBJPROP_COLOR, clrGreen);
   ObjectSetInteger(0, preFix+"TP3" + EntryIndexLine, OBJPROP_STYLE, STYLE_DOT);
   
   ObjectCreate(0, preFix+"TP4" + EntryIndexLine, OBJ_TREND, 0, iTime(Symbol(),InpTimeFrame,LastSignalIndex), LastSignalTP4Price, time, LastSignalTP4Price);
   ObjectSetInteger(0, preFix+"TP4" + EntryIndexLine, OBJPROP_COLOR, clrGreen);
   ObjectSetInteger(0, preFix+"TP4" + EntryIndexLine, OBJPROP_STYLE, STYLE_DOT);
   
   if(InpShowRanges)
   {
      ObjectCreate(0,preFix+"Range" + EntryIndexLine, OBJ_RECTANGLE, 0, iTime(Symbol(),InpTimeFrame,LastSignalIndex+sensitivity), BufferRangeLower[i], iTime(Symbol(),InpTimeFrame,LastSignalIndex), BufferRangeUpper[i]);
      ObjectSetInteger(0,preFix+"Range" + EntryIndexLine, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0,preFix+"Range" + EntryIndexLine, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0,preFix+"Range" + EntryIndexLine, OBJPROP_BACK, false);
      
      //Fib50
      ObjectCreate(0, preFix+"Fib50" + EntryIndexLine, OBJ_TREND, 0, iTime(Symbol(),InpTimeFrame,LastSignalIndex+sensitivity), BufferSupport[i], time, BufferSupport[i]);
      ObjectSetInteger(0, preFix+"Fib50" + EntryIndexLine, OBJPROP_COLOR, clrGreen);
      ObjectSetInteger(0, preFix+"Fib50" + EntryIndexLine, OBJPROP_STYLE, STYLE_DOT);
      
      //Fib50
      ObjectCreate(0, preFix+"Fib236" + EntryIndexLine, OBJ_TREND, 0, iTime(Symbol(),InpTimeFrame,LastSignalIndex+sensitivity), BufferFib236[i], time, BufferFib236[i]);
      ObjectSetInteger(0, preFix+"Fib236" + EntryIndexLine, OBJPROP_COLOR, clrYellow);
      ObjectSetInteger(0, preFix+"Fib236" + EntryIndexLine, OBJPROP_STYLE, STYLE_DOT);
      
      //Fib50
      ObjectCreate(0, preFix+"Fib786" + EntryIndexLine, OBJ_TREND, 0, iTime(Symbol(),InpTimeFrame,LastSignalIndex+sensitivity), BufferFib786[i], time, BufferFib786[i]);
      ObjectSetInteger(0, preFix+"Fib786" + EntryIndexLine, OBJPROP_COLOR, clrYellow);
      ObjectSetInteger(0, preFix+"Fib786" + EntryIndexLine, OBJPROP_STYLE, STYLE_DOT);
      
   }
   
   EntryIndexLine++;               
}

void DoSell(int i)
{
   datetime time = iTime(Symbol(), InpTimeFrame, i);
   double close = iClose(Symbol(), InpTimeFrame, i);
   double open = iOpen(Symbol(), InpTimeFrame, i);
   
   LastSignalIndex = i;
   LastSignalEntryPrice = close; // BufferSell[i];
   
   if (LastSignalEntryPrice==0)
   {
      LastSignalEntryPrice = close;
   }
   
   ObjectCreate(0, preFix+"Entry" + EntryIndexLine, OBJ_TREND, 0, iTime(Symbol(),InpTimeFrame,LastSignalIndex), LastSignalEntryPrice, time, LastSignalEntryPrice);
   ObjectSetInteger(0, preFix+"Entry" + EntryIndexLine, OBJPROP_COLOR, clrYellow);
   ObjectSetInteger(0, preFix+"Entry" + EntryIndexLine, OBJPROP_STYLE, STYLE_DOT);
       
   if(!InpUseTVIMBACalculations)
   {
      if(InpSLFixed)
      {
         LastSignalSLPrice = BufferResistance[i];         
      }
      else
      {
         LastSignalSLPrice = BufferFib236[i];
      }  
   }
   else
   {
      if(InpSLFixed)
      {    
         LastSignalSLPrice = LastSignalEntryPrice * (1 + InpSLPercentage/100);
      }
      else
      {       
         LastSignalSLPrice = BufferFib236[i] * (1 + InpSLPercentage/100);
      }  
   }
   
   ObjectCreate(0, preFix+"SL" + EntryIndexLine, OBJ_TREND, 0, iTime(Symbol(),InpTimeFrame,LastSignalIndex), LastSignalSLPrice, time, LastSignalSLPrice);
   ObjectSetInteger(0, preFix+"SL" + EntryIndexLine, OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, preFix+"SL" + EntryIndexLine, OBJPROP_STYLE, STYLE_DOT);
   
   LastSignalRiskInPrice = LastSignalSLPrice - LastSignalEntryPrice;
   
   if(!InpUseTVIMBACalculations)
   {
      LastSignalTP1Price = LastSignalEntryPrice - LastSignalRiskInPrice * InpTp1RR;
      LastSignalTP2Price = LastSignalEntryPrice - LastSignalRiskInPrice * InpTp2RR;
      LastSignalTP3Price = LastSignalEntryPrice - LastSignalRiskInPrice * InpTp3RR;
      LastSignalTP4Price = LastSignalEntryPrice - LastSignalRiskInPrice * InpTp4RR;
   }
   else
   {
      //IMBA implementation
      LastSignalTP1Price = LastSignalEntryPrice * (1 - InpTp1RR/100);
      LastSignalTP2Price = LastSignalEntryPrice * (1 - InpTp2RR/100);
      LastSignalTP3Price = LastSignalEntryPrice * (1 - InpTp3RR/100);
      LastSignalTP4Price = LastSignalEntryPrice * (1 - InpTp4RR/100);
   }  
   
   ObjectCreate(0, preFix+"TP1" + EntryIndexLine, OBJ_TREND, 0, iTime(Symbol(),InpTimeFrame,LastSignalIndex), LastSignalTP1Price, time, LastSignalTP1Price);
   ObjectSetInteger(0, preFix+"TP1" + EntryIndexLine, OBJPROP_COLOR, clrGreen);
   ObjectSetInteger(0, preFix+"TP1" + EntryIndexLine, OBJPROP_STYLE, STYLE_DOT);
   
   ObjectCreate(0, preFix+"TP2" + EntryIndexLine, OBJ_TREND, 0, iTime(Symbol(),InpTimeFrame,LastSignalIndex), LastSignalTP2Price, time, LastSignalTP2Price);
   ObjectSetInteger(0, preFix+"TP2" + EntryIndexLine, OBJPROP_COLOR, clrGreen);
   ObjectSetInteger(0, preFix+"TP2" + EntryIndexLine, OBJPROP_STYLE, STYLE_DOT);
   
   ObjectCreate(0, preFix+"TP3" + EntryIndexLine, OBJ_TREND, 0, iTime(Symbol(),InpTimeFrame,LastSignalIndex), LastSignalTP3Price, time, LastSignalTP3Price);
   ObjectSetInteger(0, preFix+"TP3" + EntryIndexLine, OBJPROP_COLOR, clrGreen);
   ObjectSetInteger(0, preFix+"TP3" + EntryIndexLine, OBJPROP_STYLE, STYLE_DOT);
   
   ObjectCreate(0, preFix+"TP4" + EntryIndexLine, OBJ_TREND, 0, iTime(Symbol(),InpTimeFrame,LastSignalIndex), LastSignalTP4Price, time, LastSignalTP4Price);
   ObjectSetInteger(0, preFix+"TP4" + EntryIndexLine, OBJPROP_COLOR, clrGreen);
   ObjectSetInteger(0, preFix+"TP4" + EntryIndexLine, OBJPROP_STYLE, STYLE_DOT);
   
   if(InpShowRanges)
   {
      ObjectCreate(0,preFix+"Range" + EntryIndexLine, OBJ_RECTANGLE, 0, iTime(Symbol(),InpTimeFrame,LastSignalIndex+sensitivity), BufferRangeLower[i], iTime(Symbol(),InpTimeFrame,LastSignalIndex), BufferRangeUpper[i]);
      ObjectSetInteger(0,preFix+"Range" + EntryIndexLine, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0,preFix+"Range" + EntryIndexLine, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0,preFix+"Range" + EntryIndexLine, OBJPROP_BACK, false);
      
      //Fib50
      ObjectCreate(0, preFix+"Fib50" + EntryIndexLine, OBJ_TREND, 0, iTime(Symbol(),InpTimeFrame,LastSignalIndex+sensitivity), BufferSupport[i], time, BufferSupport[i]);
      ObjectSetInteger(0, preFix+"Fib50" + EntryIndexLine, OBJPROP_COLOR, clrGreen);
      ObjectSetInteger(0, preFix+"Fib50" + EntryIndexLine, OBJPROP_STYLE, STYLE_DOT);
      
      //Fib50
      ObjectCreate(0, preFix+"Fib236" + EntryIndexLine, OBJ_TREND, 0, iTime(Symbol(),InpTimeFrame,LastSignalIndex+sensitivity), BufferFib236[i], time, BufferFib236[i]);
      ObjectSetInteger(0, preFix+"Fib236" + EntryIndexLine, OBJPROP_COLOR, clrYellow);
      ObjectSetInteger(0, preFix+"Fib236" + EntryIndexLine, OBJPROP_STYLE, STYLE_DOT);
      
      //Fib50
      ObjectCreate(0, preFix+"Fib786" + EntryIndexLine, OBJ_TREND, 0, iTime(Symbol(),InpTimeFrame,LastSignalIndex+sensitivity), BufferFib786[i], time, BufferFib786[i]);
      ObjectSetInteger(0, preFix+"Fib786" + EntryIndexLine, OBJPROP_COLOR, clrYellow);
      ObjectSetInteger(0, preFix+"Fib786" + EntryIndexLine, OBJPROP_STYLE, STYLE_DOT);
      
   }
      
   EntryIndexLine++;
}

ENUM_POSITION_TYPE OpenTrade(ENUM_ORDER_TYPE type, double sl, double tp, double volume, string comment)
{
    if(sl == EMPTY_VALUE)
        sl = 0;

    double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(Symbol(), SYMBOL_ASK) : SymbolInfoDouble(Symbol(), SYMBOL_BID);

    int digits = (int) SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
    
    price = NormalizeDouble(price, digits);
    sl = NormalizeDouble(sl, digits);
    tp = NormalizeDouble(tp, digits);

    string strComment = InpTradeComment + "_#" + comment;
    
    bool check = CheckMoneyForTrade(Symbol(),volume,type);
    if(!check)
      return -1;

    if(Trade.PositionOpen(Symbol(), type, volume, price, sl, tp, strComment))
    {
        Print_("New Order opened -- " + strComment);        
        return ((ENUM_POSITION_TYPE) type);
    }
    else
    {
        Print_("Failed to open New Order -- " + strComment);
    }
    return -1;
}

bool CheckMoneyForTrade(string symb,double lots,ENUM_ORDER_TYPE type)
  {
//--- Getting the opening price
   MqlTick mqltick;
   SymbolInfoTick(symb,mqltick);
   double price=mqltick.ask;
   if(type==ORDER_TYPE_SELL)
      price=mqltick.bid;
//--- values of the required and free margin
   double margin,free_margin=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   //--- call of the checking function
   if(!OrderCalcMargin(type,symb,lots,price,margin))
     {
      //--- something went wrong, report and return false
      Print("Error in ",__FUNCTION__," code=",GetLastError());
      return(false);
     }
   //--- if there are insufficient funds to perform the operation
   if(margin>free_margin)
     {
      //--- report the error and return false
      Print("Not enough money for ",EnumToString(type)," ",lots," ",symb," Error code=",GetLastError());
      return(false);
     }
//--- checking successful
   return(true);
  }
  
string TruncateNumber(string number, int decimalPoints=2)
{
   int start_index = StringFind(number, ".");
   if (start_index == -1) return number;
   
   string vals[2] = {"", ""};
   StringSplit(number, '.', vals);
   
   if (StringLen(vals[1]) <= decimalPoints ) return number;
   
   return number; // StringConcatenate(vals[0], ".", StringSubstr(vals[1], 0, 2));
}

bool is_long_trend_started;
bool is_short_trend_started;
bool is_long_trend;
bool is_short_trend;
bool is_trend_change;

double prevValue = 0;

string arrowUp = CharToString(233);
string arrowDown = CharToString(234);

void GetIMBAvalues(int history)
{
   ENUM_TIMEFRAMES timeFrame = Period();
   
   if(InpTimeFrame != PERIOD_CURRENT)
   {
      timeFrame = InpTimeFrame;
   }
   
   for (int i = history; i > 0; i--)
   {     
      double high_line = iHigh(Symbol(), timeFrame, iHighest(Symbol(), timeFrame, MODE_HIGH, sensitivity, i));
      double low_line = iLow(Symbol(), timeFrame, iLowest(Symbol(), timeFrame, MODE_LOW, sensitivity, i));
      datetime timePrev = iTime(Symbol(), timeFrame, i+1);
      datetime time = iTime(Symbol(), timeFrame, i);
      datetime time0 = iTime(Symbol(), timeFrame, i-1);
      
      double channel_range = high_line - low_line;
      double fib_236 = high_line - channel_range * 0.236;
      double fib_382 = high_line - channel_range * 0.382;
      double fib_5 = high_line - channel_range * 0.5;
      double fib_618 = high_line - channel_range * 0.618;
      double fib_786 = high_line - channel_range * 0.786;
      double imba_trend_line = fib_5;
                  
      index++;
      ResizeArrays();
      
      BufferResistance[i] = 0;
      BufferSupport[i] = 0;
      
      BufferSell[i] = 0;
      BufferBuy[i] = 0;
      
      BufferRangeUpper[i] = high_line;
      BufferRangeLower[i] = low_line;
      BufferFib236[i] = fib_236;
      BufferFib786[i] = fib_786;
      BufferTime[i] = time;
      
      double close = iClose(Symbol(), timeFrame, i);
      double high = iHigh(Symbol(), timeFrame, i);
      double low = iLow(Symbol(), timeFrame, i);
      
      // CAN LONG/SHORT
      if(!is_long_trend && !is_short_trend) //INIT
      {
         if(close >= imba_trend_line)
         {
            is_long_trend = true;
         }
         else if(close <= imba_trend_line)
         {
            is_short_trend = true;
         }
      }
      
      bool can_long = close >= imba_trend_line && close >= fib_236 && !is_long_trend;
      bool can_short = close <= imba_trend_line && close <= fib_786 && !is_short_trend;
                  

      if (can_long)
      {
         is_long_trend = true;
         is_short_trend = false;
         is_long_trend_started = true;
         is_short_trend_started = false;
         is_trend_change = true;
         BufferSupport[i] = imba_trend_line;
      }
      else if (can_short)
      {
         is_short_trend = true;
         is_long_trend = false;
         is_short_trend_started = true;
         is_long_trend_started = false;
         is_trend_change = true;
         BufferResistance[i] = imba_trend_line;
      }
      else //Reset all to false - in some sort of a range (NOT trending)
      {
         //keep previos values and colors
         if(is_long_trend)
         {
            BufferSupport[i] = imba_trend_line;
         }
         else if(is_short_trend)
         {
            BufferResistance[i] = imba_trend_line;
         }
      
         is_trend_change = false;
         can_long = false;
         can_short = false;
         is_short_trend_started = false;
         is_long_trend_started = false;
      }      
      
      if(is_trend_change)
      {
         if(is_long_trend)
         {
            ObjectCreate(0,preFix+"ArrowUp"+i, OBJ_ARROW_BUY, 0, time, close);
            ObjectSetInteger(0,preFix+"ArrowUp"+i,OBJPROP_COLOR,clrLime);
            ObjectSetInteger(0,preFix+"ArrowUp"+i,OBJPROP_BACK,false);
            ObjectSetInteger(0,preFix+"ArrowUp"+i,OBJPROP_WIDTH,3);
            
            ObjectCreate(0,preFix+"ArrowUp2"+i, OBJ_TEXT, 0, time, BufferSupport[i]);
            ObjectSetString(0, preFix+"ArrowUp2"+i, OBJPROP_TEXT, arrowUp);
            ObjectSetString(0, preFix+"ArrowUp2"+i, OBJPROP_FONT, "Wingdings");
            ObjectSetInteger(0, preFix+"ArrowUp2"+i, OBJPROP_FONTSIZE, 14);            
            ObjectSetInteger(0,preFix+"ArrowUp2"+i,OBJPROP_COLOR,clrLime);
            ObjectSetInteger(0,preFix+"ArrowUp2"+i,OBJPROP_BACK,false);
            ObjectSetInteger(0,preFix+"ArrowUp2"+i,OBJPROP_WIDTH,3);
            ObjectSetInteger(0,preFix+"ArrowUp2"+i,OBJPROP_ANCHOR, ANCHOR_CENTER);              
            
            is_trend_change = false;
            
            if(InpShowSignalLines)
            {
               ObjectCreate(0, preFix + "BuyLine" + i, OBJ_VLINE, 0, time, 0);
               ObjectSetInteger(0, preFix + "BuyLine" + i, OBJPROP_COLOR, clrGreen);
               ObjectSetInteger(0, preFix + "BuyLine" + i, OBJPROP_STYLE, STYLE_DOT);
            }
            
            BufferBuy[i] = high;
            
         }
         if(is_short_trend)
         {            
            ObjectCreate(0,preFix+"ArrowDown"+i, OBJ_ARROW_SELL, 0, time, close);
            ObjectSetInteger(0,preFix+"ArrowDown"+i,OBJPROP_COLOR,clrRed); 
            ObjectSetInteger(0,preFix+"ArrowDown"+i,OBJPROP_BACK,false); 
            ObjectSetInteger(0,preFix+"ArrowDown"+i,OBJPROP_WIDTH,3);
            
            ObjectCreate(0,preFix+"ArrowDown2"+i, OBJ_TEXT, 0, time, BufferResistance[i]);
            ObjectSetString(0, preFix+"ArrowDown2"+i, OBJPROP_TEXT, arrowDown);
            ObjectSetString(0, preFix+"ArrowDown2"+i, OBJPROP_FONT, "Wingdings");
            ObjectSetInteger(0, preFix+"ArrowDown2"+i, OBJPROP_FONTSIZE, 14);            
            ObjectSetInteger(0,preFix+"ArrowDown2"+i,OBJPROP_COLOR,clrRed); 
            ObjectSetInteger(0,preFix+"ArrowDown2"+i,OBJPROP_BACK,false); 
            ObjectSetInteger(0,preFix+"ArrowDown2"+i,OBJPROP_WIDTH,3);
            ObjectSetInteger(0,preFix+"ArrowDown2"+i,OBJPROP_ANCHOR,ANCHOR_CENTER); 
            
            is_trend_change = false;
            
            if(InpShowSignalLines)
            {
               ObjectCreate(0, preFix + "SellLine" + i, OBJ_VLINE, 0, time, 0);
               ObjectSetInteger(0, preFix + "SellLine" + i, OBJPROP_COLOR, clrRed);
               ObjectSetInteger(0, preFix + "SellLine" + i, OBJPROP_STYLE, STYLE_DOT);
            }
            
            BufferSell[i] = low;
         }
      } 
      
      if(InpShowIMBATrendLine)
      {
         if(BufferSupport[i] != 0)
         {            
            ObjectCreate(0, preFix+"Trend" + i, OBJ_TREND, 0, time, BufferSupport[i], time0, BufferSupport[i]);
            ObjectSetInteger(0, preFix+"Trend" + i, OBJPROP_COLOR, clrGreen);
            ObjectSetInteger(0, preFix+"Trend" + i, OBJPROP_STYLE, STYLE_SOLID);
            
            ObjectCreate(0, preFix+"TrendLink" + i, OBJ_TREND, 0, time, prevValue, time, BufferSupport[i]);
            ObjectSetInteger(0, preFix+"TrendLink" + i, OBJPROP_COLOR, clrGreen);
            ObjectSetInteger(0, preFix+"TrendLink" + i, OBJPROP_STYLE, STYLE_SOLID);
            
            prevValue = BufferSupport[i];
         }
         else if (BufferResistance[i] != 0)
         {
            ObjectCreate(0, preFix+"Trend" + i, OBJ_TREND, 0, time, BufferResistance[i], time0, BufferResistance[i]);
            ObjectSetInteger(0, preFix+"Trend" + i, OBJPROP_COLOR, clrRed);
            ObjectSetInteger(0, preFix+"Trend" + i, OBJPROP_STYLE, STYLE_SOLID);
            
            ObjectCreate(0, preFix+"TrendLink" + i, OBJ_TREND, 0, time, prevValue, time, BufferResistance[i]);
            ObjectSetInteger(0, preFix+"TrendLink" + i, OBJPROP_COLOR, clrRed);
            ObjectSetInteger(0, preFix+"TrendLink" + i, OBJPROP_STYLE, STYLE_SOLID);
            
            prevValue = BufferResistance[i];
         }
      }
   }      
}

int indexAfter = hist+1;

void GetIMBAvalues()
{
   ENUM_TIMEFRAMES timeFrame = Period();
   
   if(InpTimeFrame != PERIOD_CURRENT)
   {
      timeFrame = InpTimeFrame;
   }
   
   int i = 1;
   
   double high_line = iHigh(Symbol(), timeFrame, iHighest(Symbol(), timeFrame, MODE_HIGH, sensitivity, i));
   double low_line = iLow(Symbol(), timeFrame, iLowest(Symbol(), timeFrame, MODE_LOW, sensitivity, i));
   datetime timePrev = iTime(Symbol(), timeFrame, i+1);
   datetime time = iTime(Symbol(), timeFrame, i);
   datetime time0 = iTime(Symbol(), timeFrame, i-1);
   
   double channel_range = high_line - low_line;
   double fib_236 = high_line - channel_range * 0.236;
   double fib_382 = high_line - channel_range * 0.382;
   double fib_5 = high_line - channel_range * 0.5;
   double fib_618 = high_line - channel_range * 0.618;
   double fib_786 = high_line - channel_range * 0.786;
   double imba_trend_line = fib_5;               
   
   BufferResistance[i] = 0;
   BufferSupport[i] = 0;
   
   BufferSell[i] = 0;
   BufferBuy[i] = 0;
   
   BufferRangeUpper[i] = high_line;
   BufferRangeLower[i] = low_line;
   BufferFib236[i] = fib_236;
   BufferFib786[i] = fib_786;
   BufferTime[i] = time;
   
   double close = iClose(Symbol(), timeFrame, i);
   double high = iHigh(Symbol(), timeFrame, i);
   double low = iLow(Symbol(), timeFrame, i);
   
   // CAN LONG/SHORT
   if(!is_long_trend && !is_short_trend) //INIT
   {
      if(close >= imba_trend_line)
      {
         is_long_trend = true;
      }
      else if(close <= imba_trend_line)
      {
         is_short_trend = true;
      }
   }
   
   bool can_long = close >= imba_trend_line && close >= fib_236 && !is_long_trend;
   bool can_short = close <= imba_trend_line && close <= fib_786 && !is_short_trend;
               

   if (can_long)
   {
      is_long_trend = true;
      is_short_trend = false;
      is_long_trend_started = true;
      is_short_trend_started = false;
      is_trend_change = true;
      BufferSupport[i] = imba_trend_line;
   }
   else if (can_short)
   {
      is_short_trend = true;
      is_long_trend = false;
      is_short_trend_started = true;
      is_long_trend_started = false;
      is_trend_change = true;
      BufferResistance[i] = imba_trend_line;
   }
   else //Reset all to false - in some sort of a range (NOT trending)
   {
      //keep previos values and colors
      if(is_long_trend)
      {
         BufferSupport[i] = imba_trend_line;
      }
      else if(is_short_trend)
      {
         BufferResistance[i] = imba_trend_line;
      }
   
      is_trend_change = false;
      can_long = false;
      can_short = false;
      is_short_trend_started = false;
      is_long_trend_started = false;
   }      
   
   if(is_trend_change)
   {
      if(is_long_trend)
      {
         ObjectCreate(0,preFix+"ArrowUp"+indexAfter, OBJ_ARROW_BUY, 0, time, close);
         ObjectSetInteger(0,preFix+"ArrowUp"+indexAfter,OBJPROP_COLOR,clrLime);
         ObjectSetInteger(0,preFix+"ArrowUp"+indexAfter,OBJPROP_BACK,false);
         ObjectSetInteger(0,preFix+"ArrowUp"+indexAfter,OBJPROP_WIDTH,3);
         
         ObjectCreate(0,preFix+"ArrowUp2"+indexAfter, OBJ_TEXT, 0, time, BufferSupport[i]);
         ObjectSetString(0, preFix+"ArrowUp2"+indexAfter, OBJPROP_TEXT, arrowUp);
         ObjectSetString(0, preFix+"ArrowUp2"+indexAfter, OBJPROP_FONT, "Wingdings");
         ObjectSetInteger(0, preFix+"ArrowUp2"+indexAfter, OBJPROP_FONTSIZE, 14);            
         ObjectSetInteger(0,preFix+"ArrowUp2"+indexAfter,OBJPROP_COLOR,clrLime);
         ObjectSetInteger(0,preFix+"ArrowUp2"+indexAfter,OBJPROP_BACK,false);
         ObjectSetInteger(0,preFix+"ArrowUp2"+indexAfter,OBJPROP_WIDTH,3);
         ObjectSetInteger(0,preFix+"ArrowUp2"+indexAfter,OBJPROP_ANCHOR, ANCHOR_CENTER);              
         
         is_trend_change = false;
         
         if(InpShowSignalLines)
         {
            ObjectCreate(0, preFix + "BuyLine" + indexAfter, OBJ_VLINE, 0, time, 0);
            ObjectSetInteger(0, preFix + "BuyLine" + indexAfter, OBJPROP_COLOR, clrGreen);
            ObjectSetInteger(0, preFix + "BuyLine" + indexAfter, OBJPROP_STYLE, STYLE_DOT);
         }
         
         BufferBuy[i] = high;
         
      }
      if(is_short_trend)
      {            
         ObjectCreate(0,preFix+"ArrowDown"+indexAfter, OBJ_ARROW_SELL, 0, time, close);
         ObjectSetInteger(0,preFix+"ArrowDown"+indexAfter,OBJPROP_COLOR,clrRed); 
         ObjectSetInteger(0,preFix+"ArrowDown"+indexAfter,OBJPROP_BACK,false); 
         ObjectSetInteger(0,preFix+"ArrowDown"+indexAfter,OBJPROP_WIDTH,3);
         
         ObjectCreate(0,preFix+"ArrowDown2"+indexAfter, OBJ_TEXT, 0, time, BufferResistance[i]);
         ObjectSetString(0, preFix+"ArrowDown2"+indexAfter, OBJPROP_TEXT, arrowDown);
         ObjectSetString(0, preFix+"ArrowDown2"+indexAfter, OBJPROP_FONT, "Wingdings");
         ObjectSetInteger(0, preFix+"ArrowDown2"+indexAfter, OBJPROP_FONTSIZE, 14);            
         ObjectSetInteger(0,preFix+"ArrowDown2"+indexAfter,OBJPROP_COLOR,clrRed); 
         ObjectSetInteger(0,preFix+"ArrowDown2"+indexAfter,OBJPROP_BACK,false); 
         ObjectSetInteger(0,preFix+"ArrowDown2"+indexAfter,OBJPROP_WIDTH,3);
         ObjectSetInteger(0,preFix+"ArrowDown2"+indexAfter,OBJPROP_ANCHOR,ANCHOR_CENTER); 
         
         is_trend_change = false;
         
         if(InpShowSignalLines)
         {
            ObjectCreate(0, preFix + "SellLine" + indexAfter, OBJ_VLINE, 0, time, 0);
            ObjectSetInteger(0, preFix + "SellLine" + indexAfter, OBJPROP_COLOR, clrRed);
            ObjectSetInteger(0, preFix + "SellLine" + indexAfter, OBJPROP_STYLE, STYLE_DOT);
         }
         
         BufferSell[i] = low;
      }
   } 
   
   if(InpShowIMBATrendLine)
   {
      if(BufferSupport[i] != 0)
      {            
         ObjectCreate(0, preFix+"Trend" + indexAfter, OBJ_TREND, 0, time, BufferSupport[i], time0, BufferSupport[i]);
         ObjectSetInteger(0, preFix+"Trend" + indexAfter, OBJPROP_COLOR, clrGreen);
         ObjectSetInteger(0, preFix+"Trend" + indexAfter, OBJPROP_STYLE, STYLE_SOLID);
         
         ObjectCreate(0, preFix+"TrendLink" + indexAfter, OBJ_TREND, 0, time, prevValue, time, BufferSupport[i]);
         ObjectSetInteger(0, preFix+"TrendLink" + indexAfter, OBJPROP_COLOR, clrGreen);
         ObjectSetInteger(0, preFix+"TrendLink" + indexAfter, OBJPROP_STYLE, STYLE_SOLID);
         
         prevValue = BufferSupport[i];
      }
      else if (BufferResistance[i] != 0)
      {
         ObjectCreate(0, preFix+"Trend" + indexAfter, OBJ_TREND, 0, time, BufferResistance[i], time0, BufferResistance[i]);
         ObjectSetInteger(0, preFix+"Trend" + indexAfter, OBJPROP_COLOR, clrRed);
         ObjectSetInteger(0, preFix+"Trend" + indexAfter, OBJPROP_STYLE, STYLE_SOLID);
         
         ObjectCreate(0, preFix+"TrendLink" + indexAfter, OBJ_TREND, 0, time, prevValue, time, BufferResistance[i]);
         ObjectSetInteger(0, preFix+"TrendLink" + indexAfter, OBJPROP_COLOR, clrRed);
         ObjectSetInteger(0, preFix+"TrendLink" + indexAfter, OBJPROP_STYLE, STYLE_SOLID);
         
         prevValue = BufferResistance[i];
      }
   }
   indexAfter++;
}

void ShowObjects(string match)
{
   for (int i = ObjectsTotal(0) - 1; i >= 0; i--)
   {
      string str = ObjectName(0, i);

      if(StringFind(str, match, 0) == -1)
         continue;

      Print_("Showing object " + str);
      ObjectSetInteger(0, str, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   }
}

void HideObjects(string match)
{
   for (int i = ObjectsTotal(0) - 1; i >= 0; i--)
   {
      string str = ObjectName(0, i);

      if(StringFind(str, match, 0) == -1)
         continue;

      Print_("Hiding object " + str);
      ObjectSetInteger(0, str, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
   }
}
