//
// EA Studio Portfolio Expert Advisor
//
// Created with: Expert Advisor Studio
// Website: https://eas.forexsb.com
//
// Copyright 2023, Forex Software Ltd.
//
// This Portfolio Expert works in MetaTrader 4.
// It opens separate positions for each strategy.
// Every position has an unique magic number, which corresponds to the index of the strategy.
//
// Risk Disclosure
//
// Futures and forex trading contains substantial risk and is not for every investor.
// An investor could potentially lose all or more than the initial investment.
// Risk capital is money that can be lost without jeopardizing ones’ financial security or life style.
// Only risk capital should be used for trading and only those with sufficient risk capital should consider trading.

#property copyright "Forex Software Ltd."
#property version   "3.4"
#property strict

static input double Entry_Amount       =    0.01; // Entry lots
static input int    Base_Magic_Number  =     100; // Base Magic Number

static input string ___Options_______  = "-----"; // --- Options ---
static input int    Max_Open_Positions =     100; // Max Open Positions

#define TRADE_RETRY_COUNT   4
#define TRADE_RETRY_WAIT  100
#define OP_FLAT            -1

// Session time is set in seconds from 00:00
const int  sessionSundayOpen           =     0; // 00:00
const int  sessionSundayClose          = 86400; // 24:00
const int  sessionMondayThursdayOpen   =  3600; // 01:00
const int  sessionMondayThursdayClose  = 79200; // 22:00
const int  sessionFridayOpen           =  3600; // 01:00
const int  sessionFridayClose          = 79200; // 22:00
const bool sessionIgnoreSunday         = false;
const bool sessionCloseAtSessionClose  = false;
const bool sessionCloseAtFridayClose   = true;

const int    strategiesCount = 63;
const double sigma        = 0.000001;
const int    requiredBars = 99;

datetime barTime;
double   stopLevel;
double   pip;
bool     setProtectionSeparately = false;

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
enum OrderScope
  {
   ORDER_SCOPE_UNDEFINED,
   ORDER_SCOPE_ENTRY,
   ORDER_SCOPE_EXIT
  };
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
enum OrderDirection
  {
   ORDER_DIRECTION_NONE,
   ORDER_DIRECTION_BUY,
   ORDER_DIRECTION_SELL,
   ORDER_DIRECTION_BOTH
  };
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
struct Position
  {
   int    Type;
   int    Ticket;
   int    MagicNumber;
   double Lots;
   double Price;
   double StopLoss;
   double TakeProfit;
  };
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
struct Signal
  {
   int            MagicNumber;
   OrderScope     Scope;
   OrderDirection Direction;
   int            StopLossPips;
   int            TakeProfitPips;
   bool           IsTrailingStop;
   bool           OppositeReverse;
  };
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int OnInit()
  {
   barTime   = Time[0];
   stopLevel = MarketInfo(_Symbol, MODE_STOPLEVEL);
   pip       = GetPipValue();

   return ValidateInit();
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTick()
  {
   if (ArraySize(Time) < requiredBars)
      return;

   if ( IsForceSessionClose() )
     {
      CloseAllPositions();
      return;
     }

   if (Time[0] > barTime)
     {
      barTime = Time[0];
      OnBar();
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnBar()
  {
   if ( IsOutOfSession() )
      return;

   Signal signalList[];
   SetSignals(signalList);
   int signalsCount = ArraySize(signalList);

   for (int i = 0; i < signalsCount; i++)
     {
      Signal signal = signalList[i];
      ManageSignal(signal);
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ManageSignal(Signal &signal)
  {
   Position position = CreatePosition(signal.MagicNumber);

   if (position.Type != OP_FLAT && signal.Scope == ORDER_SCOPE_EXIT)
     {
      if ( (signal.Direction == ORDER_DIRECTION_BOTH) ||
           (position.Type == OP_BUY  && signal.Direction == ORDER_DIRECTION_SELL) ||
           (position.Type == OP_SELL && signal.Direction == ORDER_DIRECTION_BUY ) )
        {
         ClosePosition(position);
        }
     }

   if (position.Type != OP_FLAT && signal.Scope == ORDER_SCOPE_EXIT && signal.IsTrailingStop)
     {
      double trailingStop = GetTrailingStopPrice(position, signal.StopLossPips);
      Print(trailingStop);
      ManageTrailingStop(position, trailingStop);
     }

   if (position.Type != OP_FLAT && signal.OppositeReverse)
     {
      if ( (position.Type == OP_BUY  && signal.Direction == ORDER_DIRECTION_SELL) ||
           (position.Type == OP_SELL && signal.Direction == ORDER_DIRECTION_BUY ) )
        {
         ClosePosition(position);
         ManageSignal(signal);
         return;
        }
     }

   if (position.Type == OP_FLAT && signal.Scope == ORDER_SCOPE_ENTRY)
     {
      if (signal.Direction == ORDER_DIRECTION_BUY || signal.Direction == ORDER_DIRECTION_SELL)
        {
         if ( CountPositions() < Max_Open_Positions )
            OpenPosition(signal);
        }
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int CountPositions()
  {
   int minMagic = GetMagicNumber(0);
   int maxMagic = GetMagicNumber(strategiesCount);
   int posTotal = OrdersTotal();
   int count    = 0;

   for (int posIndex = posTotal - 1; posIndex >= 0; posIndex--)
     {
      if ( OrderSelect(posIndex, SELECT_BY_POS, MODE_TRADES) &&
           OrderSymbol() == _Symbol &&
           OrderCloseTime()== 0 )
        {
         int magicNumber = OrderMagicNumber();
         if (magicNumber >= minMagic && magicNumber <= maxMagic)
            count++;
        }
     }

   return count;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Position CreatePosition(int magicNumber)
  {
   Position position;
   position.MagicNumber = magicNumber;
   position.Type        = OP_FLAT;
   position.Ticket      = 0;
   position.Lots        = 0;
   position.Price       = 0;
   position.StopLoss    = 0;
   position.TakeProfit  = 0;

   int total = OrdersTotal();
   for (int pos = total - 1; pos >= 0; pos--)
     {
      if (OrderSelect(pos, SELECT_BY_POS, MODE_TRADES) &&
          OrderSymbol()      == _Symbol &&
          OrderMagicNumber() == magicNumber &&
          OrderCloseTime()   == 0)
        {
         position.Type       = OrderType();
         position.Lots       = OrderLots();
         position.Ticket     = OrderTicket();
         position.Price      = OrderOpenPrice();
         position.StopLoss   = OrderStopLoss();
         position.TakeProfit = OrderTakeProfit();
         break;
        }
     }

   return position;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal CreateEntrySignal(int strategyIndex, bool canOpenLong,   bool canOpenShort,
                         int stopLossPips,  int takeProfitPips, bool isTrailingStop,
                         bool oppositeReverse = false)
  {
   Signal signal;

   signal.MagicNumber     = GetMagicNumber(strategyIndex);
   signal.Scope           = ORDER_SCOPE_ENTRY;
   signal.StopLossPips    = stopLossPips;
   signal.TakeProfitPips  = takeProfitPips;
   signal.IsTrailingStop  = isTrailingStop;
   signal.OppositeReverse = oppositeReverse;
   signal.Direction       = canOpenLong && canOpenShort ? ORDER_DIRECTION_BOTH
                                         : canOpenLong  ? ORDER_DIRECTION_BUY
                                         : canOpenShort ? ORDER_DIRECTION_SELL
                                                        : ORDER_DIRECTION_NONE;

   return signal;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal CreateExitSignal(int strategyIndex, bool canCloseLong,   bool canCloseShorts,
                        int stopLossPips,  int  takeProfitPips, bool isTrailingStop)
  {
   Signal signal;

   signal.MagicNumber     = GetMagicNumber(strategyIndex);
   signal.Scope           = ORDER_SCOPE_EXIT;
   signal.StopLossPips    = stopLossPips;
   signal.TakeProfitPips  = takeProfitPips;
   signal.IsTrailingStop  = isTrailingStop;
   signal.OppositeReverse = false;
   signal.Direction       = canCloseLong && canCloseShorts ? ORDER_DIRECTION_BOTH
                                          : canCloseLong   ? ORDER_DIRECTION_SELL
                                          : canCloseShorts ? ORDER_DIRECTION_BUY
                                                           : ORDER_DIRECTION_NONE;

   return signal;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OpenPosition(Signal &signal)
  {
   for (int attempt = 0; attempt < TRADE_RETRY_COUNT; attempt++)
     {
      int    ticket     = 0;
      int    lastError  = 0;
      bool   modified   = false;
      int    command    = OrderDirectionToCommand(signal.Direction);
      double amount     = Entry_Amount;
      int    magicNum   = signal.MagicNumber;
      string comment    = IntegerToString(magicNum);
      color  arrowColor = command == OP_BUY ? clrGreen : clrRed;

      if ( IsTradeContextFree() )
        {
         double price      = command == OP_BUY ? Ask() : Bid();
         double stopLoss   = GetStopLossPrice(command, signal.StopLossPips);
         double takeProfit = GetTakeProfitPrice(command, signal.TakeProfitPips);
         bool   isSLOrTP   = stopLoss > _Point || takeProfit > _Point;

         if (setProtectionSeparately)
           {
            // Send an entry order without SL and TP
            ticket = OrderSend(_Symbol, command, amount, price, 10, 0, 0, comment, magicNum, 0, arrowColor);

            // If the order is successful, modify the position with the corresponding SL and TP
            if (ticket > 0 && isSLOrTP)
               modified = OrderModify(ticket, 0, stopLoss, takeProfit, 0, clrBlue);
           }
         else
           {
            // Send an entry order with SL and TP
            ticket    = OrderSend(_Symbol, command, amount, price, 10, stopLoss, takeProfit, comment, magicNum, 0, arrowColor);
            lastError = GetLastError();

            // If order fails, check if it is because inability to set SL or TP
            if (ticket <= 0 && lastError == 130)
              {
               // Send an entry order without SL and TP
               ticket = OrderSend(_Symbol, command, amount, price, 10, 0, 0, comment, magicNum, 0, arrowColor);

               // Try to set SL and TP
               if (ticket > 0 && isSLOrTP)
                  modified = OrderModify(ticket, 0, stopLoss, takeProfit, 0, clrBlue);

               // Mark the expert to set SL and TP with a separate order
               if (ticket > 0 && modified)
                 {
                  setProtectionSeparately = true;
                  Print("Detected ECN type position protection.");
                 }
              }
           }
        }

      if (ticket > 0)
         break;

      lastError = GetLastError();

      if (lastError != 135 && lastError != 136 && lastError != 137 && lastError != 138)
         break;

      Sleep(TRADE_RETRY_WAIT);
      Print("Open Position retry no: " + IntegerToString(attempt + 2));
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ClosePosition(Position &position)
  {
   for (int attempt = 0; attempt < TRADE_RETRY_COUNT; attempt++)
     {
      bool closed    = 0;
      int  lastError = 0;

      if ( IsTradeContextFree() )
        {
         double price = position.Type == OP_BUY ? Bid() : Ask();
         closed    = OrderClose(position.Ticket, position.Lots, price, 10, clrYellow);
         lastError = GetLastError();
        }

      if (closed)
        {
         position.Type       = OP_FLAT;
         position.Lots       = 0;
         position.Price      = 0;
         position.StopLoss   = 0;
         position.TakeProfit = 0;
         break;
        }

      if (lastError == 4108)
         break;

      Sleep(TRADE_RETRY_WAIT);
      Print("Close Position retry no: " + IntegerToString(attempt + 2));
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ModifyPosition(Position &position)
  {
   for (int attempt = 0; attempt < TRADE_RETRY_COUNT; attempt++)
     {
      bool modified  = 0;
      int  lastError = 0;

      if (IsTradeContextFree())
        {
         modified  = OrderModify(position.Ticket, 0, position.StopLoss, position.TakeProfit, 0, clrBlue);
         lastError = GetLastError();
        }

      if (modified)
        {
         position = CreatePosition(position.MagicNumber);
         break;
        }

      if (lastError == 4108)
         break;

      Sleep(TRADE_RETRY_WAIT);
      Print("Modify Position retry no: " + IntegerToString(attempt + 2));
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CloseAllPositions()
  {
   for (int i = 0; i < strategiesCount; i++)
     {
      Position position = CreatePosition( GetMagicNumber(i) );

      if (position.Type == OP_BUY || position.Type == OP_SELL)
         ClosePosition(position);
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetStopLossPrice(int command, int stopLossPips)
  {
   if (stopLossPips == 0)
      return 0;

   double delta    = MathMax(pip * stopLossPips, _Point * stopLevel);
   double stopLoss = command == OP_BUY ? Bid() - delta : Ask() + delta;

   return NormalizeDouble(stopLoss, _Digits);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetTakeProfitPrice(int command, int takeProfitPips)
  {
   if (takeProfitPips == 0)
      return 0;

   double delta      = MathMax(pip * takeProfitPips, _Point * stopLevel);
   double takeProfit = command == OP_BUY ? Bid() + delta : Ask() - delta;

   return NormalizeDouble(takeProfit, _Digits);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetTrailingStopPrice(Position &position, int stopLoss)
  {
   double bid = Bid();
   double ask = Ask();
   double spread = ask - bid;
   double stopLevelPoints = _Point * stopLevel;
   double stopLossPoints  = pip * stopLoss;

   if (position.Type == OP_BUY)
     {
      double newStopLoss = High(1) - stopLossPoints;
      if (position.StopLoss <= newStopLoss - pip)
         return newStopLoss < bid
                 ? newStopLoss >= bid - stopLevelPoints
                    ? bid - stopLevelPoints
                    : newStopLoss
                 : bid;
     }

   if (position.Type == OP_SELL)
     {
      double newStopLoss = Low(1) + spread + stopLossPoints;
      if (position.StopLoss >= newStopLoss + pip)
         return newStopLoss > ask
                 ? newStopLoss <= ask + stopLevelPoints
                    ? ask + stopLevelPoints
                    : newStopLoss
                 : ask;
     }

   return position.StopLoss;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ManageTrailingStop(Position &position, double trailingStop)
  {
   if ( (position.Type == OP_BUY  && MathAbs(trailingStop - Bid()) < _Point) ||
        (position.Type == OP_SELL && MathAbs(trailingStop - Ask()) < _Point) )
     {
      ClosePosition(position);
      return;
     }

   if (MathAbs(trailingStop - position.StopLoss) > _Point)
     {
      position.StopLoss = NormalizeDouble(trailingStop, _Digits);
      ModifyPosition(position);
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsTradeContextFree()
  {
   if ( IsTradeAllowed() )
      return true;

   uint startWait = GetTickCount();
   Print("Trade context is busy! Waiting...");

   while (true)
     {
      if ( IsStopped() )
         return false;

      uint diff = GetTickCount() - startWait;
      if (diff > 30 * 1000)
        {
         Print("The waiting limit exceeded!");
         return false;
        }

      if ( IsTradeAllowed() )
        {
         RefreshRates();
         return true;
        }

      Sleep(TRADE_RETRY_WAIT);
     }

   return true;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsOutOfSession()
  {
   int dayOfWeek    = DayOfWeek();
   int periodStart  = int(Time(0) % 86400);
   int periodLength = PeriodSeconds(_Period);
   int periodFix    = periodStart + (sessionCloseAtSessionClose ? periodLength : 0);
   int friBarFix    = periodStart + (sessionCloseAtFridayClose || sessionCloseAtSessionClose ? periodLength : 0);

   return dayOfWeek == 0 && sessionIgnoreSunday ? true
        : dayOfWeek == 0 ? periodStart < sessionSundayOpen         || periodFix > sessionSundayClose
        : dayOfWeek  < 5 ? periodStart < sessionMondayThursdayOpen || periodFix > sessionMondayThursdayClose
                         : periodStart < sessionFridayOpen         || friBarFix > sessionFridayClose;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsForceSessionClose()
  {
   if (!sessionCloseAtFridayClose && !sessionCloseAtSessionClose)
      return false;

   int dayOfWeek = DayOfWeek();
   int periodEnd = int(Time(0) % 86400) + PeriodSeconds(_Period);

   return dayOfWeek == 0 && sessionCloseAtSessionClose ? periodEnd > sessionSundayClose
        : dayOfWeek  < 5 && sessionCloseAtSessionClose ? periodEnd > sessionMondayThursdayClose
        : dayOfWeek == 5 ? periodEnd > sessionFridayClose : false;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double Bid()
  {
   return MarketInfo(_Symbol, MODE_BID);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double Ask()
  {
   return MarketInfo(_Symbol, MODE_ASK);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
datetime Time(int bar)
  {
   return Time[bar];
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double Open(int bar)
  {
   return Open[bar];
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double High(int bar)
  {
   return High[bar];
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double Low(int bar)
  {
   return Low[bar];
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double Close(int bar)
  {
   return Close[bar];
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetPipValue()
  {
   return _Digits == 4 || _Digits == 5 ? 0.0001
        : _Digits == 2 || _Digits == 3 ? 0.01
                        : _Digits == 1 ? 0.1 : 1;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int GetMagicNumber(int strategyIndex)
  {
   return 1000 * Base_Magic_Number + strategyIndex;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int OrderDirectionToCommand(OrderDirection dir)
  {
   return dir == ORDER_DIRECTION_BUY  ? OP_BUY
        : dir == ORDER_DIRECTION_SELL ? OP_SELL
                                      : OP_FLAT;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void SetSignals(Signal &signalList[])
  {
   int i = 0;
   ArrayResize(signalList, 2 * strategiesCount);
   HideTestIndicators(true);

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":21,"takeProfit":670,"useStopLoss":true,"useTakeProfit":true,"isTrailingStop":true},"openFilters":[{"name":"Awesome Oscillator","listIndexes":[1,0,0,0,0],"numValues":[0,0,0,0,0,0]},{"name":"Envelopes","listIndexes":[2,3,0,0,0],"numValues":[15,0.07,0,0,0,0]}],"closeFilters":[{"name":"Moving Average","listIndexes":[2,0,3,0,0],"numValues":[39,0,0,0,0,0]},{"name":"Alligator","listIndexes":[1,3,4,0,0],"numValues":[39,22,22,9,9,1]}]} */
   signalList[i++] = GetExitSignal_00();
   signalList[i++] = GetEntrySignal_00();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":0,"stopLoss":20,"takeProfit":0,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":true},"openFilters":[{"name":"Awesome Oscillator","listIndexes":[4,0,0,0,0],"numValues":[0,0,0,0,0,0]}],"closeFilters":[{"name":"RSI","listIndexes":[0,3,0,0,0],"numValues":[12,30,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_01();
   signalList[i++] = GetEntrySignal_01();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":18,"takeProfit":0,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":true},"openFilters":[{"name":"Bollinger Bands","listIndexes":[4,3,0,0,0],"numValues":[50,2.35,0,0,0,0]},{"name":"ADX","listIndexes":[0,0,0,0,0],"numValues":[32,0,0,0,0,0]}],"closeFilters":[{"name":"Alligator","listIndexes":[3,1,4,0,0],"numValues":[39,26,26,12,12,5]},{"name":"Moving Average","listIndexes":[1,0,3,0,0],"numValues":[6,8,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_02();
   signalList[i++] = GetEntrySignal_02();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":26,"takeProfit":0,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":true},"openFilters":[{"name":"Williams' Percent Range","listIndexes":[5,0,0,0,0],"numValues":[24,-45,0,0,0,0]},{"name":"Moving Average","listIndexes":[5,0,3,0,0],"numValues":[35,19,0,0,0,0]},{"name":"Moving Average","listIndexes":[5,0,3,0,0],"numValues":[40,0,0,0,0,0]}],"closeFilters":[{"name":"Directional Indicators","listIndexes":[1,0,0,0,0],"numValues":[19,0,0,0,0,0]},{"name":"Average True Range","listIndexes":[6,0,0,0,0],"numValues":[29,0.01,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_03();
   signalList[i++] = GetEntrySignal_03();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":13,"takeProfit":597,"useStopLoss":true,"useTakeProfit":true,"isTrailingStop":true},"openFilters":[{"name":"MACD Signal","listIndexes":[1,3,0,0,0],"numValues":[21,45,6,0,0,0]}],"closeFilters":[{"name":"Stochastic","listIndexes":[2,0,0,0,0],"numValues":[15,15,4,76,0,0]},{"name":"RSI","listIndexes":[6,3,0,0,0],"numValues":[9,30,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_04();
   signalList[i++] = GetEntrySignal_04();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":25,"takeProfit":766,"useStopLoss":true,"useTakeProfit":true,"isTrailingStop":true},"openFilters":[{"name":"Awesome Oscillator","listIndexes":[4,0,0,0,0],"numValues":[0,0,0,0,0,0]}],"closeFilters":[{"name":"DeMarker","listIndexes":[2,0,0,0,0],"numValues":[42,0.79,0,0,0,0]},{"name":"Commodity Channel Index","listIndexes":[5,5,0,0,0],"numValues":[42,0,0,0,0,0]},{"name":"Directional Indicators","listIndexes":[2,0,0,0,0],"numValues":[46,0,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_05();
   signalList[i++] = GetEntrySignal_05();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":15,"takeProfit":705,"useStopLoss":true,"useTakeProfit":true,"isTrailingStop":true},"openFilters":[{"name":"MACD Signal","listIndexes":[1,3,0,0,0],"numValues":[18,49,3,0,0,0]}],"closeFilters":[{"name":"Stochastic","listIndexes":[0,0,0,0,0],"numValues":[16,10,16,20,0,0]}]} */
   signalList[i++] = GetExitSignal_06();
   signalList[i++] = GetEntrySignal_06();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":21,"takeProfit":86,"useStopLoss":true,"useTakeProfit":true,"isTrailingStop":true},"openFilters":[{"name":"MACD Signal","listIndexes":[1,3,0,0,0],"numValues":[19,43,6,0,0,0]}],"closeFilters":[{"name":"RSI","listIndexes":[1,3,0,0,0],"numValues":[39,30,0,0,0,0]},{"name":"Williams' Percent Range","listIndexes":[0,0,0,0,0],"numValues":[28,-20,0,0,0,0]},{"name":"DeMarker","listIndexes":[0,0,0,0,0],"numValues":[17,0,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_07();
   signalList[i++] = GetEntrySignal_07();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":11,"takeProfit":0,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":true},"openFilters":[{"name":"MACD Signal","listIndexes":[1,3,0,0,0],"numValues":[24,33,7,0,0,0]}],"closeFilters":[{"name":"Directional Indicators","listIndexes":[0,0,0,0,0],"numValues":[10,0,0,0,0,0]},{"name":"Envelopes","listIndexes":[4,3,0,0,0],"numValues":[38,0.07,0,0,0,0]},{"name":"Bollinger Bands","listIndexes":[5,3,0,0,0],"numValues":[46,3.48,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_08();
   signalList[i++] = GetEntrySignal_08();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":0,"stopLoss":26,"takeProfit":0,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":true},"openFilters":[{"name":"Williams' Percent Range","listIndexes":[5,0,0,0,0],"numValues":[50,-36,0,0,0,0]}],"closeFilters":[{"name":"Williams' Percent Range","listIndexes":[0,0,0,0,0],"numValues":[39,-20,0,0,0,0]},{"name":"Williams' Percent Range","listIndexes":[4,0,0,0,0],"numValues":[12,-62,0,0,0,0]},{"name":"Stochastic Signal","listIndexes":[0,0,0,0,0],"numValues":[10,6,7,0,0,0]}]} */
   signalList[i++] = GetExitSignal_09();
   signalList[i++] = GetEntrySignal_09();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":0,"stopLoss":13,"takeProfit":597,"useStopLoss":true,"useTakeProfit":true,"isTrailingStop":true},"openFilters":[{"name":"MACD Signal","listIndexes":[1,3,0,0,0],"numValues":[21,45,6,0,0,0]}],"closeFilters":[{"name":"Stochastic","listIndexes":[2,0,0,0,0],"numValues":[15,15,4,76,0,0]},{"name":"RSI","listIndexes":[4,3,0,0,0],"numValues":[42,65,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_010();
   signalList[i++] = GetEntrySignal_010();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":14,"takeProfit":325,"useStopLoss":true,"useTakeProfit":true,"isTrailingStop":true},"openFilters":[{"name":"Moving Average","listIndexes":[5,2,3,0,0],"numValues":[34,24,0,0,0,0]},{"name":"ADX","listIndexes":[1,0,0,0,0],"numValues":[27,0,0,0,0,0]}],"closeFilters":[{"name":"Awesome Oscillator","listIndexes":[3,0,0,0,0],"numValues":[0,0,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_011();
   signalList[i++] = GetEntrySignal_011();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":0,"stopLoss":22,"takeProfit":699,"useStopLoss":true,"useTakeProfit":true,"isTrailingStop":true},"openFilters":[{"name":"Stochastic","listIndexes":[7,0,0,0,0],"numValues":[12,9,1,20,0,0]},{"name":"ADX","listIndexes":[3,0,0,0,0],"numValues":[26,21,0,0,0,0]}],"closeFilters":[{"name":"Commodity Channel Index","listIndexes":[0,5,0,0,0],"numValues":[46,0,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_012();
   signalList[i++] = GetEntrySignal_012();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":14,"takeProfit":702,"useStopLoss":true,"useTakeProfit":true,"isTrailingStop":true},"openFilters":[{"name":"Directional Indicators","listIndexes":[1,0,0,0,0],"numValues":[14,0,0,0,0,0]},{"name":"Stochastic","listIndexes":[0,0,0,0,0],"numValues":[12,7,9,20,0,0]},{"name":"On Balance Volume","listIndexes":[0,0,0,0,0],"numValues":[0,0,0,0,0,0]}],"closeFilters":[{"name":"DeMarker","listIndexes":[1,0,0,0,0],"numValues":[40,0,0,0,0,0]},{"name":"Average True Range","listIndexes":[0,0,0,0,0],"numValues":[29,0.01,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_013();
   signalList[i++] = GetEntrySignal_013();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":22,"takeProfit":0,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":true},"openFilters":[{"name":"Alligator","listIndexes":[10,1,4,0,0],"numValues":[36,21,21,8,8,4]}],"closeFilters":[{"name":"Alligator","listIndexes":[6,3,4,0,0],"numValues":[41,15,15,2,2,1]}]} */
   signalList[i++] = GetExitSignal_014();
   signalList[i++] = GetEntrySignal_014();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":22,"takeProfit":0,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":true},"openFilters":[{"name":"Momentum","listIndexes":[5,3,0,0,0],"numValues":[22,100,0,0,0,0]}],"closeFilters":[{"name":"Alligator","listIndexes":[4,3,4,0,0],"numValues":[42,17,17,8,8,1]},{"name":"Awesome Oscillator","listIndexes":[2,0,0,0,0],"numValues":[0.0009,0,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_015();
   signalList[i++] = GetEntrySignal_015();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":23,"takeProfit":0,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":true},"openFilters":[{"name":"RSI","listIndexes":[5,3,0,0,0],"numValues":[10,63,0,0,0,0]},{"name":"Average True Range","listIndexes":[0,0,0,0,0],"numValues":[5,0.01,0,0,0,0]}],"closeFilters":[{"name":"Bollinger Bands","listIndexes":[2,3,0,0,0],"numValues":[29,3.6,0,0,0,0]},{"name":"Momentum","listIndexes":[1,3,0,0,0],"numValues":[29,100,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_016();
   signalList[i++] = GetEntrySignal_016();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":20,"takeProfit":551,"useStopLoss":true,"useTakeProfit":true,"isTrailingStop":true},"openFilters":[{"name":"Awesome Oscillator","listIndexes":[4,0,0,0,0],"numValues":[0,0,0,0,0,0]}],"closeFilters":[{"name":"Commodity Channel Index","listIndexes":[0,5,0,0,0],"numValues":[17,0,0,0,0,0]},{"name":"ADX","listIndexes":[6,0,0,0,0],"numValues":[43,0,0,0,0,0]},{"name":"Alligator","listIndexes":[5,3,4,0,0],"numValues":[41,20,20,12,12,3]}]} */
   signalList[i++] = GetExitSignal_017();
   signalList[i++] = GetEntrySignal_017();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":12,"takeProfit":989,"useStopLoss":true,"useTakeProfit":true,"isTrailingStop":true},"openFilters":[{"name":"Moving Average","listIndexes":[5,1,3,0,0],"numValues":[26,0,0,0,0,0]},{"name":"Alligator","listIndexes":[3,2,4,0,0],"numValues":[17,14,14,9,9,2]}],"closeFilters":[{"name":"DeMarker","listIndexes":[2,0,0,0,0],"numValues":[9,0.54,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_018();
   signalList[i++] = GetEntrySignal_018();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":13,"takeProfit":54,"useStopLoss":true,"useTakeProfit":true,"isTrailingStop":true},"openFilters":[{"name":"Alligator","listIndexes":[10,1,4,0,0],"numValues":[35,23,23,7,7,2]}],"closeFilters":[{"name":"Alligator","listIndexes":[9,3,4,0,0],"numValues":[32,25,25,11,11,5]},{"name":"ADX","listIndexes":[6,0,0,0,0],"numValues":[45,0,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_019();
   signalList[i++] = GetEntrySignal_019();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":26,"takeProfit":0,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":true},"openFilters":[{"name":"Momentum","listIndexes":[5,3,0,0,0],"numValues":[22,100,0,0,0,0]}],"closeFilters":[{"name":"Moving Average","listIndexes":[0,0,3,0,0],"numValues":[15,3,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_020();
   signalList[i++] = GetEntrySignal_020();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":0,"stopLoss":26,"takeProfit":0,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":true},"openFilters":[{"name":"Directional Indicators","listIndexes":[1,0,0,0,0],"numValues":[19,0,0,0,0,0]}],"closeFilters":[{"name":"Average True Range","listIndexes":[1,0,0,0,0],"numValues":[46,0.01,0,0,0,0]},{"name":"Envelopes","listIndexes":[2,3,0,0,0],"numValues":[28,0.44,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_021();
   signalList[i++] = GetEntrySignal_021();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":0,"stopLoss":21,"takeProfit":670,"useStopLoss":true,"useTakeProfit":true,"isTrailingStop":true},"openFilters":[{"name":"Awesome Oscillator","listIndexes":[1,0,0,0,0],"numValues":[0,0,0,0,0,0]},{"name":"Envelopes","listIndexes":[2,3,0,0,0],"numValues":[15,0.07,0,0,0,0]}],"closeFilters":[{"name":"Moving Average","listIndexes":[2,0,3,0,0],"numValues":[39,0,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_022();
   signalList[i++] = GetEntrySignal_022();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":22,"takeProfit":429,"useStopLoss":true,"useTakeProfit":true,"isTrailingStop":true},"openFilters":[{"name":"MACD Signal","listIndexes":[1,3,0,0,0],"numValues":[14,49,3,0,0,0]}],"closeFilters":[{"name":"Average True Range","listIndexes":[3,0,0,0,0],"numValues":[34,0.0017,0,0,0,0]},{"name":"Awesome Oscillator","listIndexes":[0,0,0,0,0],"numValues":[0,0,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_023();
   signalList[i++] = GetEntrySignal_023();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":0,"stopLoss":12,"takeProfit":0,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":true},"openFilters":[{"name":"Moving Average","listIndexes":[3,0,3,0,0],"numValues":[7,5,0,0,0,0]},{"name":"MACD Signal","listIndexes":[1,3,0,0,0],"numValues":[17,45,3,0,0,0]}],"closeFilters":[{"name":"Stochastic","listIndexes":[0,0,0,0,0],"numValues":[15,1,11,20,0,0]},{"name":"Williams' Percent Range","listIndexes":[2,0,0,0,0],"numValues":[15,-26,0,0,0,0]},{"name":"Alligator","listIndexes":[3,2,4,0,0],"numValues":[17,11,11,2,2,1]}]} */
   signalList[i++] = GetExitSignal_024();
   signalList[i++] = GetEntrySignal_024();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":15,"takeProfit":217,"useStopLoss":true,"useTakeProfit":true,"isTrailingStop":true},"openFilters":[{"name":"Stochastic","listIndexes":[5,0,0,0,0],"numValues":[11,8,10,20,0,0]}],"closeFilters":[{"name":"Stochastic","listIndexes":[3,0,0,0,0],"numValues":[15,12,13,39,0,0]},{"name":"Momentum","listIndexes":[7,3,0,0,0],"numValues":[29,100,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_025();
   signalList[i++] = GetEntrySignal_025();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":0,"stopLoss":20,"takeProfit":0,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":true},"openFilters":[{"name":"Moving Average","listIndexes":[5,0,3,0,0],"numValues":[13,0,0,0,0,0]}],"closeFilters":[{"name":"Momentum","listIndexes":[1,3,0,0,0],"numValues":[7,100,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_026();
   signalList[i++] = GetEntrySignal_026();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":0,"stopLoss":17,"takeProfit":528,"useStopLoss":true,"useTakeProfit":true,"isTrailingStop":true},"openFilters":[{"name":"MACD Signal","listIndexes":[1,3,0,0,0],"numValues":[20,43,4,0,0,0]},{"name":"Stochastic Signal","listIndexes":[3,0,0,0,0],"numValues":[10,5,4,0,0,0]},{"name":"Momentum","listIndexes":[2,3,0,0,0],"numValues":[38,100,0,0,0,0]}],"closeFilters":[{"name":"Stochastic Signal","listIndexes":[3,0,0,0,0],"numValues":[12,5,4,0,0,0]},{"name":"Momentum","listIndexes":[7,3,0,0,0],"numValues":[27,100,0,0,0,0]},{"name":"Momentum","listIndexes":[5,3,0,0,0],"numValues":[42,99,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_027();
   signalList[i++] = GetEntrySignal_027();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":26,"takeProfit":983,"useStopLoss":true,"useTakeProfit":true,"isTrailingStop":true},"openFilters":[{"name":"Envelopes","listIndexes":[4,3,0,0,0],"numValues":[28,0.22,0,0,0,0]}],"closeFilters":[{"name":"RSI","listIndexes":[2,3,0,0,0],"numValues":[35,72,0,0,0,0]},{"name":"Awesome Oscillator","listIndexes":[4,0,0,0,0],"numValues":[0,0,0,0,0,0]},{"name":"RSI","listIndexes":[1,3,0,0,0],"numValues":[40,30,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_028();
   signalList[i++] = GetEntrySignal_028();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":14,"takeProfit":0,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":true},"openFilters":[{"name":"Momentum","listIndexes":[5,3,0,0,0],"numValues":[27,100,0,0,0,0]}],"closeFilters":[{"name":"Standard Deviation","listIndexes":[3,3,0,0,0],"numValues":[48,0.0029,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_029();
   signalList[i++] = GetEntrySignal_029();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":18,"takeProfit":0,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":true},"openFilters":[{"name":"Directional Indicators","listIndexes":[1,0,0,0,0],"numValues":[20,0,0,0,0,0]}],"closeFilters":[{"name":"ADX","listIndexes":[3,0,0,0,0],"numValues":[13,22,0,0,0,0]},{"name":"Momentum","listIndexes":[2,3,0,0,0],"numValues":[12,100,0,0,0,0]},{"name":"Moving Average","listIndexes":[6,0,3,0,0],"numValues":[27,10,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_030();
   signalList[i++] = GetEntrySignal_030();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":12,"takeProfit":0,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":true},"openFilters":[{"name":"Moving Averages Crossover","listIndexes":[0,0,0,0,0],"numValues":[5,36,0,0,0,0]}],"closeFilters":[{"name":"Moving Average","listIndexes":[1,0,3,0,0],"numValues":[34,6,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_031();
   signalList[i++] = GetEntrySignal_031();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":0,"stopLoss":21,"takeProfit":0,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":true},"openFilters":[{"name":"On Balance Volume","listIndexes":[3,0,0,0,0],"numValues":[0,0,0,0,0,0]}],"closeFilters":[{"name":"Directional Indicators","listIndexes":[2,0,0,0,0],"numValues":[11,0,0,0,0,0]},{"name":"RSI","listIndexes":[2,3,0,0,0],"numValues":[49,62,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_032();
   signalList[i++] = GetEntrySignal_032();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":19,"takeProfit":0,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":true},"openFilters":[{"name":"Stochastic Signal","listIndexes":[1,0,0,0,0],"numValues":[4,2,2,0,0,0]},{"name":"Momentum","listIndexes":[7,3,0,0,0],"numValues":[28,100,0,0,0,0]},{"name":"Momentum","listIndexes":[2,3,0,0,0],"numValues":[32,100,0,0,0,0]}],"closeFilters":[{"name":"Commodity Channel Index","listIndexes":[2,5,0,0,0],"numValues":[40,0,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_033();
   signalList[i++] = GetEntrySignal_033();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":20,"takeProfit":0,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":true},"openFilters":[{"name":"Moving Average","listIndexes":[5,3,3,0,0],"numValues":[44,0,0,0,0,0]}],"closeFilters":[{"name":"Commodity Channel Index","listIndexes":[0,5,0,0,0],"numValues":[19,0,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_034();
   signalList[i++] = GetEntrySignal_034();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":26,"takeProfit":0,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":true},"openFilters":[{"name":"Awesome Oscillator","listIndexes":[4,0,0,0,0],"numValues":[-0.0006,0,0,0,0,0]}],"closeFilters":[{"name":"Accelerator Oscillator","listIndexes":[0,0,0,0,0],"numValues":[0,0,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_035();
   signalList[i++] = GetEntrySignal_035();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":24,"takeProfit":0,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":true},"openFilters":[{"name":"Bollinger Bands","listIndexes":[2,3,0,0,0],"numValues":[32,2.63,0,0,0,0]},{"name":"Moving Average","listIndexes":[2,0,3,0,0],"numValues":[6,0,0,0,0,0]}],"closeFilters":[{"name":"Bollinger Bands","listIndexes":[1,3,0,0,0],"numValues":[22,3.68,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_036();
   signalList[i++] = GetEntrySignal_036();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":19,"takeProfit":707,"useStopLoss":true,"useTakeProfit":true,"isTrailingStop":true},"openFilters":[{"name":"Commodity Channel Index","listIndexes":[5,5,0,0,0],"numValues":[17,0,0,0,0,0]},{"name":"Moving Average","listIndexes":[0,0,3,0,0],"numValues":[8,0,0,0,0,0]}],"closeFilters":[{"name":"RSI","listIndexes":[3,3,0,0,0],"numValues":[31,17,0,0,0,0]},{"name":"Commodity Channel Index","listIndexes":[0,5,0,0,0],"numValues":[31,0,0,0,0,0]},{"name":"Alligator","listIndexes":[5,0,4,0,0],"numValues":[36,23,23,15,15,5]}]} */
   signalList[i++] = GetExitSignal_037();
   signalList[i++] = GetEntrySignal_037();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":16,"takeProfit":0,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":true},"openFilters":[{"name":"Moving Average","listIndexes":[5,0,3,0,0],"numValues":[47,25,0,0,0,0]}],"closeFilters":[{"name":"Moving Averages Crossover","listIndexes":[2,0,0,0,0],"numValues":[17,45,0,0,0,0]},{"name":"DeMarker","listIndexes":[6,0,0,0,0],"numValues":[12,0,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_038();
   signalList[i++] = GetEntrySignal_038();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":24,"takeProfit":797,"useStopLoss":true,"useTakeProfit":true,"isTrailingStop":true},"openFilters":[{"name":"MACD Signal","listIndexes":[1,3,0,0,0],"numValues":[17,42,3,0,0,0]},{"name":"Commodity Channel Index","listIndexes":[1,5,0,0,0],"numValues":[33,0,0,0,0,0]},{"name":"Williams' Percent Range","listIndexes":[3,0,0,0,0],"numValues":[8,-54,0,0,0,0]}],"closeFilters":[{"name":"DeMarker","listIndexes":[1,0,0,0,0],"numValues":[43,0,0,0,0,0]},{"name":"DeMarker","listIndexes":[7,0,0,0,0],"numValues":[24,0,0,0,0,0]},{"name":"Momentum","listIndexes":[2,3,0,0,0],"numValues":[32,100,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_039();
   signalList[i++] = GetEntrySignal_039();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":12,"takeProfit":670,"useStopLoss":true,"useTakeProfit":true,"isTrailingStop":true},"openFilters":[{"name":"RSI","listIndexes":[4,3,0,0,0],"numValues":[15,30,0,0,0,0]}],"closeFilters":[{"name":"Williams' Percent Range","listIndexes":[6,0,0,0,0],"numValues":[41,-20,0,0,0,0]},{"name":"Stochastic","listIndexes":[2,0,0,0,0],"numValues":[4,1,3,66,0,0]},{"name":"Stochastic","listIndexes":[0,0,0,0,0],"numValues":[5,5,5,20,0,0]}]} */
   signalList[i++] = GetExitSignal_040();
   signalList[i++] = GetEntrySignal_040();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":0,"stopLoss":14,"takeProfit":0,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":true},"openFilters":[{"name":"Commodity Channel Index","listIndexes":[5,5,0,0,0],"numValues":[21,0,0,0,0,0]},{"name":"Standard Deviation","listIndexes":[1,3,0,0,0],"numValues":[12,0,0,0,0,0]}],"closeFilters":[{"name":"Moving Averages Crossover","listIndexes":[2,0,3,0,0],"numValues":[19,39,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_041();
   signalList[i++] = GetEntrySignal_041();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":13,"takeProfit":597,"useStopLoss":true,"useTakeProfit":true,"isTrailingStop":true},"openFilters":[{"name":"MACD Signal","listIndexes":[1,3,0,0,0],"numValues":[21,45,6,0,0,0]}],"closeFilters":[{"name":"Stochastic","listIndexes":[2,0,0,0,0],"numValues":[15,15,4,76,0,0]},{"name":"Directional Indicators","listIndexes":[2,0,0,0,0],"numValues":[17,0,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_042();
   signalList[i++] = GetEntrySignal_042();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":23,"takeProfit":899,"useStopLoss":true,"useTakeProfit":true,"isTrailingStop":true},"openFilters":[{"name":"Stochastic","listIndexes":[5,0,0,0,0],"numValues":[13,8,13,58,0,0]}],"closeFilters":[{"name":"ADX","listIndexes":[2,0,0,0,0],"numValues":[13,39,0,0,0,0]},{"name":"ADX","listIndexes":[7,0,0,0,0],"numValues":[8,0,0,0,0,0]},{"name":"Williams' Percent Range","listIndexes":[7,0,0,0,0],"numValues":[23,-20,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_043();
   signalList[i++] = GetEntrySignal_043();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":15,"takeProfit":504,"useStopLoss":true,"useTakeProfit":true,"isTrailingStop":true},"openFilters":[{"name":"Directional Indicators","listIndexes":[1,0,0,0,0],"numValues":[20,0,0,0,0,0]}],"closeFilters":[{"name":"Accelerator Oscillator","listIndexes":[1,0,0,0,0],"numValues":[0,0,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_044();
   signalList[i++] = GetEntrySignal_044();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":21,"takeProfit":0,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":true},"openFilters":[{"name":"Bollinger Bands","listIndexes":[3,3,0,0,0],"numValues":[39,1.17,0,0,0,0]},{"name":"Momentum","listIndexes":[6,3,0,0,0],"numValues":[7,100,0,0,0,0]}],"closeFilters":[{"name":"Directional Indicators","listIndexes":[1,0,0,0,0],"numValues":[48,0,0,0,0,0]},{"name":"Stochastic","listIndexes":[0,0,0,0,0],"numValues":[9,6,9,20,0,0]}]} */
   signalList[i++] = GetExitSignal_045();
   signalList[i++] = GetEntrySignal_045();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":11,"takeProfit":887,"useStopLoss":true,"useTakeProfit":true,"isTrailingStop":true},"openFilters":[{"name":"Directional Indicators","listIndexes":[1,0,0,0,0],"numValues":[19,0,0,0,0,0]}],"closeFilters":[{"name":"Standard Deviation","listIndexes":[5,3,1,0,0],"numValues":[45,0.0014,0,0,0,0]},{"name":"Awesome Oscillator","listIndexes":[1,0,0,0,0],"numValues":[0,0,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_046();
   signalList[i++] = GetEntrySignal_046();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":21,"takeProfit":670,"useStopLoss":true,"useTakeProfit":true,"isTrailingStop":true},"openFilters":[{"name":"Awesome Oscillator","listIndexes":[1,0,0,0,0],"numValues":[0,0,0,0,0,0]},{"name":"Envelopes","listIndexes":[2,3,0,0,0],"numValues":[15,0.07,0,0,0,0]}],"closeFilters":[{"name":"Alligator","listIndexes":[2,2,4,0,0],"numValues":[18,16,16,14,14,4]},{"name":"Alligator","listIndexes":[1,3,4,0,0],"numValues":[39,22,22,9,9,1]}]} */
   signalList[i++] = GetExitSignal_047();
   signalList[i++] = GetEntrySignal_047();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":15,"takeProfit":0,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":true},"openFilters":[{"name":"MACD Signal","listIndexes":[1,3,0,0,0],"numValues":[17,46,4,0,0,0]}],"closeFilters":[{"name":"Momentum","listIndexes":[1,3,0,0,0],"numValues":[13,100,0,0,0,0]},{"name":"Envelopes","listIndexes":[4,3,0,0,0],"numValues":[25,0.19,0,0,0,0]},{"name":"Stochastic Signal","listIndexes":[1,0,0,0,0],"numValues":[8,3,3,0,0,0]}]} */
   signalList[i++] = GetExitSignal_048();
   signalList[i++] = GetEntrySignal_048();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":18,"takeProfit":122,"useStopLoss":true,"useTakeProfit":true,"isTrailingStop":true},"openFilters":[{"name":"Stochastic Signal","listIndexes":[1,0,0,0,0],"numValues":[16,7,12,0,0,0]},{"name":"Bollinger Bands","listIndexes":[0,3,0,0,0],"numValues":[45,1.2,0,0,0,0]}],"closeFilters":[{"name":"DeMarker","listIndexes":[1,0,0,0,0],"numValues":[27,0,0,0,0,0]},{"name":"Awesome Oscillator","listIndexes":[3,0,0,0,0],"numValues":[0,0,0,0,0,0]},{"name":"Directional Indicators","listIndexes":[3,0,0,0,0],"numValues":[15,0,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_049();
   signalList[i++] = GetEntrySignal_049();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":18,"takeProfit":122,"useStopLoss":true,"useTakeProfit":true,"isTrailingStop":true},"openFilters":[{"name":"Stochastic Signal","listIndexes":[1,0,0,0,0],"numValues":[16,7,12,0,0,0]},{"name":"Bollinger Bands","listIndexes":[0,3,0,0,0],"numValues":[45,1.2,0,0,0,0]}],"closeFilters":[{"name":"Directional Indicators","listIndexes":[1,0,0,0,0],"numValues":[26,0,0,0,0,0]},{"name":"Alligator","listIndexes":[2,3,4,0,0],"numValues":[26,23,23,7,7,5]}]} */
   signalList[i++] = GetExitSignal_050();
   signalList[i++] = GetEntrySignal_050();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":18,"takeProfit":0,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":true},"openFilters":[{"name":"Candle Color","listIndexes":[1,0,0,0,0],"numValues":[6,1,0,0,0,0]}],"closeFilters":[{"name":"Stochastic Signal","listIndexes":[1,0,0,0,0],"numValues":[5,4,1,0,0,0]}]} */
   signalList[i++] = GetExitSignal_051();
   signalList[i++] = GetEntrySignal_051();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":21,"takeProfit":0,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":true},"openFilters":[{"name":"Williams' Percent Range","listIndexes":[5,0,0,0,0],"numValues":[12,-25,0,0,0,0]}],"closeFilters":[{"name":"Moving Average","listIndexes":[7,0,3,0,0],"numValues":[29,19,0,0,0,0]},{"name":"Moving Average","listIndexes":[2,0,3,0,0],"numValues":[10,0,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_052();
   signalList[i++] = GetEntrySignal_052();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":13,"takeProfit":54,"useStopLoss":true,"useTakeProfit":true,"isTrailingStop":true},"openFilters":[{"name":"Alligator","listIndexes":[10,1,4,0,0],"numValues":[35,23,23,7,7,2]}],"closeFilters":[{"name":"Standard Deviation","listIndexes":[0,3,0,0,0],"numValues":[6,0,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_053();
   signalList[i++] = GetEntrySignal_053();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":15,"takeProfit":0,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":true},"openFilters":[{"name":"MACD Signal","listIndexes":[1,3,0,0,0],"numValues":[17,46,4,0,0,0]}],"closeFilters":[{"name":"Directional Indicators","listIndexes":[3,0,0,0,0],"numValues":[45,0,0,0,0,0]},{"name":"Envelopes","listIndexes":[4,3,0,0,0],"numValues":[25,0.19,0,0,0,0]},{"name":"Stochastic Signal","listIndexes":[1,0,0,0,0],"numValues":[8,3,3,0,0,0]}]} */
   signalList[i++] = GetExitSignal_054();
   signalList[i++] = GetEntrySignal_054();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":21,"takeProfit":0,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":true},"openFilters":[{"name":"Alligator","listIndexes":[7,1,4,0,0],"numValues":[33,23,23,10,10,4]}],"closeFilters":[{"name":"Directional Indicators","listIndexes":[0,0,0,0,0],"numValues":[42,0,0,0,0,0]},{"name":"Stochastic Signal","listIndexes":[0,0,0,0,0],"numValues":[10,6,7,0,0,0]}]} */
   signalList[i++] = GetExitSignal_055();
   signalList[i++] = GetEntrySignal_055();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":24,"takeProfit":0,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":true},"openFilters":[{"name":"Moving Averages Crossover","listIndexes":[0,0,0,0,0],"numValues":[6,35,0,0,0,0]}],"closeFilters":[{"name":"Bollinger Bands","listIndexes":[0,3,0,0,0],"numValues":[13,1.06,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_056();
   signalList[i++] = GetEntrySignal_056();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":18,"takeProfit":122,"useStopLoss":true,"useTakeProfit":true,"isTrailingStop":true},"openFilters":[{"name":"Stochastic Signal","listIndexes":[1,0,0,0,0],"numValues":[16,7,12,0,0,0]},{"name":"Bollinger Bands","listIndexes":[0,3,0,0,0],"numValues":[45,1.2,0,0,0,0]}],"closeFilters":[{"name":"RSI","listIndexes":[0,3,0,0,0],"numValues":[46,30,0,0,0,0]},{"name":"Awesome Oscillator","listIndexes":[3,0,0,0,0],"numValues":[0,0,0,0,0,0]},{"name":"Directional Indicators","listIndexes":[3,0,0,0,0],"numValues":[15,0,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_057();
   signalList[i++] = GetEntrySignal_057();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":21,"takeProfit":0,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":true},"openFilters":[{"name":"Accelerator Oscillator","listIndexes":[4,0,0,0,0],"numValues":[0,0,0,0,0,0]},{"name":"Directional Indicators","listIndexes":[3,0,0,0,0],"numValues":[13,0,0,0,0,0]},{"name":"Average True Range","listIndexes":[2,0,0,0,0],"numValues":[26,0.0002,0,0,0,0]}],"closeFilters":[{"name":"Standard Deviation","listIndexes":[0,3,0,0,0],"numValues":[24,0,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_058();
   signalList[i++] = GetEntrySignal_058();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":14,"takeProfit":0,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":true},"openFilters":[{"name":"Commodity Channel Index","listIndexes":[5,5,0,0,0],"numValues":[19,0,0,0,0,0]},{"name":"Momentum","listIndexes":[7,3,0,0,0],"numValues":[46,100,0,0,0,0]}],"closeFilters":[{"name":"Williams' Percent Range","listIndexes":[0,0,0,0,0],"numValues":[17,-20,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_059();
   signalList[i++] = GetEntrySignal_059();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":17,"takeProfit":431,"useStopLoss":true,"useTakeProfit":true,"isTrailingStop":true},"openFilters":[{"name":"Stochastic","listIndexes":[6,0,0,0,0],"numValues":[10,2,9,20,0,0]},{"name":"Standard Deviation","listIndexes":[0,3,0,0,0],"numValues":[34,0,0,0,0,0]}],"closeFilters":[{"name":"Awesome Oscillator","listIndexes":[1,0,0,0,0],"numValues":[0,0,0,0,0,0]},{"name":"Momentum","listIndexes":[5,3,0,0,0],"numValues":[20,99,0,0,0,0]},{"name":"Average True Range","listIndexes":[0,0,0,0,0],"numValues":[44,0.01,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_060();
   signalList[i++] = GetEntrySignal_060();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":1,"stopLoss":22,"takeProfit":0,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":true},"openFilters":[{"name":"Moving Averages Crossover","listIndexes":[0,0,2,0,0],"numValues":[11,25,0,0,0,0]},{"name":"Momentum","listIndexes":[0,3,0,0,0],"numValues":[28,100,0,0,0,0]}],"closeFilters":[{"name":"Bollinger Bands","listIndexes":[4,3,0,0,0],"numValues":[8,3.15,0,0,0,0]},{"name":"Accelerator Oscillator","listIndexes":[6,0,0,0,0],"numValues":[0,0,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_061();
   signalList[i++] = GetEntrySignal_061();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":0,"stopLoss":12,"takeProfit":192,"useStopLoss":true,"useTakeProfit":true,"isTrailingStop":true},"openFilters":[{"name":"Alligator","listIndexes":[7,1,4,0,0],"numValues":[47,25,25,9,9,4]}],"closeFilters":[{"name":"Stochastic","listIndexes":[6,0,0,0,0],"numValues":[15,3,9,20,0,0]}]} */
   signalList[i++] = GetExitSignal_062();
   signalList[i++] = GetEntrySignal_062();

   HideTestIndicators(false);
   if (i != 2 * strategiesCount)
      ArrayResize(signalList, i);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_00()
  {
   // Awesome Oscillator
   double ind0val1  = iAO(NULL, 0, 1);
   double ind0val2  = iAO(NULL, 0, 2);
   bool   ind0long  = ind0val1 < ind0val2 - sigma;
   bool   ind0short = ind0val1 > ind0val2 + sigma;
   // Envelopes (Close, Simple, 15, 0.07)
   double ind1upBand1 = iEnvelopes(NULL, 0, 15, MODE_SMA, 0, PRICE_CLOSE, 0.07, MODE_UPPER, 1);
   double ind1dnBand1 = iEnvelopes(NULL, 0, 15, MODE_SMA, 0, PRICE_CLOSE, 0.07, MODE_LOWER, 1);
   double ind1upBand2 = iEnvelopes(NULL, 0, 15, MODE_SMA, 0, PRICE_CLOSE, 0.07, MODE_UPPER, 2);
   double ind1dnBand2 = iEnvelopes(NULL, 0, 15, MODE_SMA, 0, PRICE_CLOSE, 0.07, MODE_LOWER, 2);
   bool   ind1long    = Open(0) < ind1upBand1 - sigma && Open(1) > ind1upBand2 + sigma;
   bool   ind1short   = Open(0) > ind1dnBand1 + sigma && Open(1) < ind1dnBand2 - sigma;

   return CreateEntrySignal(0, ind0long && ind1long, ind0short && ind1short, 21, 670, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_00()
  {
   // Moving Average (Simple, Close, 39, 0)
   double ind2val1  = iMA(NULL, 0, 39, 0, MODE_SMA, PRICE_CLOSE, 1);
   bool   ind2long  = Open(0) > ind2val1 + sigma;
   bool   ind2short = Open(0) < ind2val1 - sigma;
   // Alligator (Smoothed, Median, 39, 22, 22, 9, 9, 1)
   double ind3val1  = iAlligator(NULL, 0, 39, 22, 22, 9, 9, 1, MODE_SMMA, PRICE_MEDIAN, MODE_GATORLIPS,  1);
   double ind3val2  = iAlligator(NULL, 0, 39, 22, 22, 9, 9, 1, MODE_SMMA, PRICE_MEDIAN, MODE_GATORLIPS,  2);
   bool   ind3long  = ind3val1 < ind3val2 - sigma;
   bool   ind3short = ind3val1 > ind3val2 + sigma;

   return CreateExitSignal(0, ind2long || ind3long, ind2short || ind3short, 21, 670, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_01()
  {
   // Awesome Oscillator, Level: 0.0000
   double ind0val1  = iAO(NULL, 0, 1);
   double ind0val2  = iAO(NULL, 0, 2);
   bool   ind0long  = ind0val1 > 0.0000 + sigma && ind0val2 < 0.0000 - sigma;
   bool   ind0short = ind0val1 < 0.0000 - sigma && ind0val2 > 0.0000 + sigma;

   return CreateEntrySignal(1, ind0long, ind0short, 20, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_01()
  {
   // RSI (Close, 12)
   double ind1val1  = iRSI(NULL, 0, 12, PRICE_CLOSE, 1);
   double ind1val2  = iRSI(NULL, 0, 12, PRICE_CLOSE, 2);
   bool   ind1long  = ind1val1 > ind1val2 + sigma;
   bool   ind1short = ind1val1 < ind1val2 - sigma;

   return CreateExitSignal(1, ind1long, ind1short, 20, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_02()
  {
   // Bollinger Bands (Close, 50, 2.35)
   double ind0upBand1 = iBands(NULL, 0, 50, 2.35, 0, PRICE_CLOSE, MODE_UPPER, 1);
   double ind0dnBand1 = iBands(NULL, 0, 50, 2.35, 0, PRICE_CLOSE, MODE_LOWER, 1);
   double ind0upBand2 = iBands(NULL, 0, 50, 2.35, 0, PRICE_CLOSE, MODE_UPPER, 2);
   double ind0dnBand2 = iBands(NULL, 0, 50, 2.35, 0, PRICE_CLOSE, MODE_LOWER, 2);
   bool   ind0long    = Open(0) < ind0dnBand1 - sigma && Open(1) > ind0dnBand2 + sigma;
   bool   ind0short   = Open(0) > ind0upBand1 + sigma && Open(1) < ind0upBand2 - sigma;
   // ADX (32)
   double ind1val1  = iADX(NULL, 0, 32, PRICE_CLOSE, 0, 1);
   double ind1val2  = iADX(NULL, 0, 32, PRICE_CLOSE, 0, 2);
   bool   ind1long  = ind1val1 > ind1val2 + sigma;
   bool   ind1short = ind1long;

   return CreateEntrySignal(2, ind0long && ind1long, ind0short && ind1short, 18, 0, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_02()
  {
   // Alligator (Exponential, Median, 39, 26, 26, 12, 12, 5)
   double ind2val1  = iAlligator(NULL, 0, 39, 26, 26, 12, 12, 5, MODE_EMA, PRICE_MEDIAN, MODE_GATORTEETH, 1);
   double ind2val2  = iAlligator(NULL, 0, 39, 26, 26, 12, 12, 5, MODE_EMA, PRICE_MEDIAN, MODE_GATORTEETH, 2);
   bool   ind2long  = ind2val1 < ind2val2 - sigma;
   bool   ind2short = ind2val1 > ind2val2 + sigma;
   // Moving Average (Simple, Close, 6, 8)
   double ind3val1  = iMA(NULL, 0, 6, 8, MODE_SMA, PRICE_CLOSE, 1);
   double ind3val2  = iMA(NULL, 0, 6, 8, MODE_SMA, PRICE_CLOSE, 2);
   bool   ind3long  = ind3val1 < ind3val2 - sigma;
   bool   ind3short = ind3val1 > ind3val2 + sigma;

   return CreateExitSignal(2, ind2long || ind3long, ind2short || ind3short, 18, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_03()
  {
   // Williams' Percent Range (24), Level: -45.0
   double ind0val1  = iWPR(NULL, 0, 24, 1);
   double ind0val2  = iWPR(NULL, 0, 24, 2);
   bool   ind0long  = ind0val1 < -45.0 - sigma && ind0val2 > -45.0 + sigma;
   bool   ind0short = ind0val1 > -100 - -45.0 + sigma && ind0val2 < -100 - -45.0 - sigma;
   // Moving Average (Simple, Close, 35, 19)
   double ind1val1  = iMA(NULL, 0, 35, 19, MODE_SMA, PRICE_CLOSE, 1);
   double ind1val2  = iMA(NULL, 0, 35, 19, MODE_SMA, PRICE_CLOSE, 2);
   bool   ind1long  = Open(0) < ind1val1 - sigma && Open(1) > ind1val2 + sigma;
   bool   ind1short = Open(0) > ind1val1 + sigma && Open(1) < ind1val2 - sigma;
   // Moving Average (Simple, Close, 40, 0)
   double ind2val1  = iMA(NULL, 0, 40, 0, MODE_SMA, PRICE_CLOSE, 1);
   double ind2val2  = iMA(NULL, 0, 40, 0, MODE_SMA, PRICE_CLOSE, 2);
   bool   ind2long  = Open(0) < ind2val1 - sigma && Open(1) > ind2val2 + sigma;
   bool   ind2short = Open(0) > ind2val1 + sigma && Open(1) < ind2val2 - sigma;

   return CreateEntrySignal(3, ind0long && ind1long && ind2long, ind0short && ind1short && ind2short, 26, 0, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_03()
  {
   // Directional Indicators (19)
   double ind3val1  = iADX(NULL, 0, 19, PRICE_CLOSE, 1, 1);
   double ind3val2  = iADX(NULL ,0 ,19, PRICE_CLOSE, 2, 1);
   double ind3val3  = iADX(NULL, 0, 19, PRICE_CLOSE, 1, 2);
   double ind3val4  = iADX(NULL ,0 ,19, PRICE_CLOSE, 2, 2);
   bool   ind3long  = ind3val1 < ind3val2 - sigma && ind3val3 > ind3val4 + sigma;
   bool   ind3short = ind3val1 > ind3val2 + sigma && ind3val3 < ind3val4 - sigma;
   // Average True Range (29)
   double ind4val1  = iATR(NULL, 0, 29, 1);
   double ind4val2  = iATR(NULL, 0, 29, 2);
   double ind4val3  = iATR(NULL, 0, 29, 3);
   bool   ind4long  = ind4val1 > ind4val2 + sigma && ind4val2 < ind4val3 - sigma;
   bool   ind4short = ind4long;

   return CreateExitSignal(3, ind3long || ind4long, ind3short || ind4short, 26, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_04()
  {
   // MACD Signal (Close, 21, 45, 6)
   double ind0val1  = iMACD(NULL, 0, 21, 45, 6, PRICE_CLOSE, MODE_MAIN, 1) - iMACD(NULL, 0, 21, 45, 6, PRICE_CLOSE ,MODE_SIGNAL, 1);
   double ind0val2  = iMACD(NULL, 0, 21, 45, 6, PRICE_CLOSE, MODE_MAIN, 2) - iMACD(NULL, 0, 21, 45, 6, PRICE_CLOSE ,MODE_SIGNAL, 2);
   bool   ind0long  = ind0val1 < 0 - sigma && ind0val2 > 0 + sigma;
   bool   ind0short = ind0val1 > 0 + sigma && ind0val2 < 0 - sigma;

   return CreateEntrySignal(4, ind0long, ind0short, 13, 597, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_04()
  {
   // Stochastic (15, 15, 4), Level: 76.0
   double ind1val1  = iStochastic(NULL, 0, 15, 15, 4, MODE_SMA, STO_LOWHIGH, MODE_MAIN, 1);
   bool   ind1long  = ind1val1 > 76.0 + sigma;
   bool   ind1short = ind1val1 < 100 - 76.0 - sigma;
   // RSI (Close, 9)
   double ind2val1  = iRSI(NULL, 0, 9, PRICE_CLOSE, 1);
   double ind2val2  = iRSI(NULL, 0, 9, PRICE_CLOSE, 2);
   double ind2val3  = iRSI(NULL, 0, 9, PRICE_CLOSE, 3);
   bool   ind2long  = ind2val1 > ind2val2 + sigma && ind2val2 < ind2val3 - sigma;
   bool   ind2short = ind2val1 < ind2val2 - sigma && ind2val2 > ind2val3 + sigma;

   return CreateExitSignal(4, ind1long || ind2long, ind1short || ind2short, 13, 597, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_05()
  {
   // Awesome Oscillator, Level: 0.0000
   double ind0val1  = iAO(NULL, 0, 1);
   double ind0val2  = iAO(NULL, 0, 2);
   bool   ind0long  = ind0val1 > 0.0000 + sigma && ind0val2 < 0.0000 - sigma;
   bool   ind0short = ind0val1 < 0.0000 - sigma && ind0val2 > 0.0000 + sigma;

   return CreateEntrySignal(5, ind0long, ind0short, 25, 766, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_05()
  {
   // DeMarker (42), Level: 0.79
   double ind1val1  = iDeMarker(NULL, 0, 42, 1);
   bool   ind1long  = ind1val1 > 0.79 + sigma;
   bool   ind1short = ind1val1 < 1 - 0.79 - sigma;
   // Commodity Channel Index (Typical, 42), Level: 0
   double ind2val1  = iCCI(NULL, 0, 42, PRICE_TYPICAL, 1);
   double ind2val2  = iCCI(NULL, 0, 42, PRICE_TYPICAL, 2);
   bool   ind2long  = ind2val1 < 0 - sigma && ind2val2 > 0 + sigma;
   bool   ind2short = ind2val1 > 0 + sigma && ind2val2 < 0 - sigma;
   // Directional Indicators (46)
   double ind3val1  = iADX(NULL, 0, 46, PRICE_CLOSE, 1, 1);
   double ind3val2  = iADX(NULL ,0 ,46, PRICE_CLOSE, 2, 1);
   bool   ind3long  = ind3val1 > ind3val2 + sigma;
   bool   ind3short = ind3val1 < ind3val2 - sigma;

   return CreateExitSignal(5, ind1long || ind2long || ind3long, ind1short || ind2short || ind3short, 25, 766, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_06()
  {
   // MACD Signal (Close, 18, 49, 3)
   double ind0val1  = iMACD(NULL, 0, 18, 49, 3, PRICE_CLOSE, MODE_MAIN, 1) - iMACD(NULL, 0, 18, 49, 3, PRICE_CLOSE ,MODE_SIGNAL, 1);
   double ind0val2  = iMACD(NULL, 0, 18, 49, 3, PRICE_CLOSE, MODE_MAIN, 2) - iMACD(NULL, 0, 18, 49, 3, PRICE_CLOSE ,MODE_SIGNAL, 2);
   bool   ind0long  = ind0val1 < 0 - sigma && ind0val2 > 0 + sigma;
   bool   ind0short = ind0val1 > 0 + sigma && ind0val2 < 0 - sigma;

   return CreateEntrySignal(6, ind0long, ind0short, 15, 705, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_06()
  {
   // Stochastic (16, 10, 16)
   double ind1val1  = iStochastic(NULL, 0, 16, 10, 16, MODE_SMA, STO_LOWHIGH, MODE_MAIN, 1);
   double ind1val2  = iStochastic(NULL, 0, 16, 10, 16, MODE_SMA, STO_LOWHIGH, MODE_MAIN, 2);
   bool   ind1long  = ind1val1 > ind1val2 + sigma;
   bool   ind1short = ind1val1 < ind1val2 - sigma;

   return CreateExitSignal(6, ind1long, ind1short, 15, 705, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_07()
  {
   // MACD Signal (Close, 19, 43, 6)
   double ind0val1  = iMACD(NULL, 0, 19, 43, 6, PRICE_CLOSE, MODE_MAIN, 1) - iMACD(NULL, 0, 19, 43, 6, PRICE_CLOSE ,MODE_SIGNAL, 1);
   double ind0val2  = iMACD(NULL, 0, 19, 43, 6, PRICE_CLOSE, MODE_MAIN, 2) - iMACD(NULL, 0, 19, 43, 6, PRICE_CLOSE ,MODE_SIGNAL, 2);
   bool   ind0long  = ind0val1 < 0 - sigma && ind0val2 > 0 + sigma;
   bool   ind0short = ind0val1 > 0 + sigma && ind0val2 < 0 - sigma;

   return CreateEntrySignal(7, ind0long, ind0short, 21, 86, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_07()
  {
   // RSI (Close, 39)
   double ind1val1  = iRSI(NULL, 0, 39, PRICE_CLOSE, 1);
   double ind1val2  = iRSI(NULL, 0, 39, PRICE_CLOSE, 2);
   bool   ind1long  = ind1val1 < ind1val2 - sigma;
   bool   ind1short = ind1val1 > ind1val2 + sigma;
   // Williams' Percent Range (28)
   double ind2val1  = iWPR(NULL, 0, 28, 1);
   double ind2val2  = iWPR(NULL, 0, 28, 2);
   bool   ind2long  = ind2val1 > ind2val2 + sigma;
   bool   ind2short = ind2val1 < ind2val2 - sigma;
   // DeMarker (17)
   double ind3val1  = iDeMarker(NULL, 0, 17, 1);
   double ind3val2  = iDeMarker(NULL, 0, 17, 2);
   bool   ind3long  = ind3val1 > ind3val2 + sigma;
   bool   ind3short = ind3val1 < ind3val2 - sigma;

   return CreateExitSignal(7, ind1long || ind2long || ind3long, ind1short || ind2short || ind3short, 21, 86, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_08()
  {
   // MACD Signal (Close, 24, 33, 7)
   double ind0val1  = iMACD(NULL, 0, 24, 33, 7, PRICE_CLOSE, MODE_MAIN, 1) - iMACD(NULL, 0, 24, 33, 7, PRICE_CLOSE ,MODE_SIGNAL, 1);
   double ind0val2  = iMACD(NULL, 0, 24, 33, 7, PRICE_CLOSE, MODE_MAIN, 2) - iMACD(NULL, 0, 24, 33, 7, PRICE_CLOSE ,MODE_SIGNAL, 2);
   bool   ind0long  = ind0val1 < 0 - sigma && ind0val2 > 0 + sigma;
   bool   ind0short = ind0val1 > 0 + sigma && ind0val2 < 0 - sigma;

   return CreateEntrySignal(8, ind0long, ind0short, 11, 0, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_08()
  {
   // Directional Indicators (10)
   double ind1val1  = iADX(NULL, 0, 10, PRICE_CLOSE, 1, 1);
   double ind1val2  = iADX(NULL ,0 ,10, PRICE_CLOSE, 2, 1);
   double ind1val3  = iADX(NULL, 0, 10, PRICE_CLOSE, 1, 2);
   double ind1val4  = iADX(NULL ,0 ,10, PRICE_CLOSE, 2, 2);
   bool   ind1long  = ind1val1 > ind1val2 + sigma && ind1val3 < ind1val4 - sigma;
   bool   ind1short = ind1val1 < ind1val2 - sigma && ind1val3 > ind1val4 + sigma;
   // Envelopes (Close, Simple, 38, 0.07)
   double ind2upBand1 = iEnvelopes(NULL, 0, 38, MODE_SMA, 0, PRICE_CLOSE, 0.07, MODE_UPPER, 1);
   double ind2dnBand1 = iEnvelopes(NULL, 0, 38, MODE_SMA, 0, PRICE_CLOSE, 0.07, MODE_LOWER, 1);
   double ind2upBand2 = iEnvelopes(NULL, 0, 38, MODE_SMA, 0, PRICE_CLOSE, 0.07, MODE_UPPER, 2);
   double ind2dnBand2 = iEnvelopes(NULL, 0, 38, MODE_SMA, 0, PRICE_CLOSE, 0.07, MODE_LOWER, 2);
   bool   ind2long    = Open(0) < ind2dnBand1 - sigma && Open(1) > ind2dnBand2 + sigma;
   bool   ind2short   = Open(0) > ind2upBand1 + sigma && Open(1) < ind2upBand2 - sigma;
   // Bollinger Bands (Close, 46, 3.48)
   double ind3upBand1 = iBands(NULL, 0, 46, 3.48, 0, PRICE_CLOSE, MODE_UPPER, 1);
   double ind3dnBand1 = iBands(NULL, 0, 46, 3.48, 0, PRICE_CLOSE, MODE_LOWER, 1);
   double ind3upBand2 = iBands(NULL, 0, 46, 3.48, 0, PRICE_CLOSE, MODE_UPPER, 2);
   double ind3dnBand2 = iBands(NULL, 0, 46, 3.48, 0, PRICE_CLOSE, MODE_LOWER, 2);
   bool   ind3long    = Open(0) > ind3dnBand1 + sigma && Open(1) < ind3dnBand2 - sigma;
   bool   ind3short   = Open(0) < ind3upBand1 - sigma && Open(1) > ind3upBand2 + sigma;

   return CreateExitSignal(8, ind1long || ind2long || ind3long, ind1short || ind2short || ind3short, 11, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_09()
  {
   // Williams' Percent Range (50), Level: -36.0
   double ind0val1  = iWPR(NULL, 0, 50, 1);
   double ind0val2  = iWPR(NULL, 0, 50, 2);
   bool   ind0long  = ind0val1 < -36.0 - sigma && ind0val2 > -36.0 + sigma;
   bool   ind0short = ind0val1 > -100 - -36.0 + sigma && ind0val2 < -100 - -36.0 - sigma;

   return CreateEntrySignal(9, ind0long, ind0short, 26, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_09()
  {
   // Williams' Percent Range (39)
   double ind1val1  = iWPR(NULL, 0, 39, 1);
   double ind1val2  = iWPR(NULL, 0, 39, 2);
   bool   ind1long  = ind1val1 > ind1val2 + sigma;
   bool   ind1short = ind1val1 < ind1val2 - sigma;
   // Williams' Percent Range (12), Level: -62.0
   double ind2val1  = iWPR(NULL, 0, 12, 1);
   double ind2val2  = iWPR(NULL, 0, 12, 2);
   bool   ind2long  = ind2val1 > -62.0 + sigma && ind2val2 < -62.0 - sigma;
   bool   ind2short = ind2val1 < -100 - -62.0 - sigma && ind2val2 > -100 - -62.0 + sigma;
   // Stochastic Signal (10, 6, 7)
   double ind3val1  = iStochastic(NULL, 0, 10, 6, 7, MODE_SMA, 0, MODE_MAIN,   1);
   double ind3val2  = iStochastic(NULL, 0, 10, 6, 7, MODE_SMA, 0, MODE_SIGNAL, 1);
   double ind3val3  = iStochastic(NULL, 0, 10, 6, 7, MODE_SMA, 0, MODE_MAIN,   2);
   double ind3val4  = iStochastic(NULL, 0, 10, 6, 7, MODE_SMA, 0, MODE_SIGNAL, 2);
   bool   ind3long  = ind3val1 > ind3val2 + sigma && ind3val3 < ind3val4 - sigma;
   bool   ind3short = ind3val1 < ind3val2 - sigma && ind3val3 > ind3val4 + sigma;

   return CreateExitSignal(9, ind1long || ind2long || ind3long, ind1short || ind2short || ind3short, 26, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_010()
  {
   // MACD Signal (Close, 21, 45, 6)
   double ind0val1  = iMACD(NULL, 0, 21, 45, 6, PRICE_CLOSE, MODE_MAIN, 1) - iMACD(NULL, 0, 21, 45, 6, PRICE_CLOSE ,MODE_SIGNAL, 1);
   double ind0val2  = iMACD(NULL, 0, 21, 45, 6, PRICE_CLOSE, MODE_MAIN, 2) - iMACD(NULL, 0, 21, 45, 6, PRICE_CLOSE ,MODE_SIGNAL, 2);
   bool   ind0long  = ind0val1 < 0 - sigma && ind0val2 > 0 + sigma;
   bool   ind0short = ind0val1 > 0 + sigma && ind0val2 < 0 - sigma;

   return CreateEntrySignal(10, ind0long, ind0short, 13, 597, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_010()
  {
   // Stochastic (15, 15, 4), Level: 76.0
   double ind1val1  = iStochastic(NULL, 0, 15, 15, 4, MODE_SMA, STO_LOWHIGH, MODE_MAIN, 1);
   bool   ind1long  = ind1val1 > 76.0 + sigma;
   bool   ind1short = ind1val1 < 100 - 76.0 - sigma;
   // RSI (Close, 42), Level: 65
   double ind2val1  = iRSI(NULL, 0, 42, PRICE_CLOSE, 1);
   double ind2val2  = iRSI(NULL, 0, 42, PRICE_CLOSE, 2);
   bool   ind2long  = ind2val1 > 65 + sigma && ind2val2 < 65 - sigma;
   bool   ind2short = ind2val1 < 100 - 65 - sigma && ind2val2 > 100 - 65 + sigma;

   return CreateExitSignal(10, ind1long || ind2long, ind1short || ind2short, 13, 597, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_011()
  {
   // Moving Average (Weighted, Close, 34, 24)
   double ind0val1  = iMA(NULL, 0, 34, 24, MODE_LWMA, PRICE_CLOSE, 1);
   double ind0val2  = iMA(NULL, 0, 34, 24, MODE_LWMA, PRICE_CLOSE, 2);
   bool   ind0long  = Open(0) < ind0val1 - sigma && Open(1) > ind0val2 + sigma;
   bool   ind0short = Open(0) > ind0val1 + sigma && Open(1) < ind0val2 - sigma;
   // ADX (27)
   double ind1val1  = iADX(NULL, 0, 27, PRICE_CLOSE, 0, 1);
   double ind1val2  = iADX(NULL, 0, 27, PRICE_CLOSE, 0, 2);
   bool   ind1long  = ind1val1 < ind1val2 - sigma;
   bool   ind1short = ind1long;

   return CreateEntrySignal(11, ind0long && ind1long, ind0short && ind1short, 14, 325, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_011()
  {
   // Awesome Oscillator, Level: 0.0000
   double ind2val1  = iAO(NULL, 0, 1);
   bool   ind2long  = ind2val1 < 0.0000 - sigma;
   bool   ind2short = ind2val1 > 0.0000 + sigma;

   return CreateExitSignal(11, ind2long, ind2short, 14, 325, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_012()
  {
   // Stochastic (12, 9, 1)
   double ind0val1  = iStochastic(NULL, 0, 12, 9, 1, MODE_SMA, STO_LOWHIGH, MODE_MAIN, 1);
   double ind0val2  = iStochastic(NULL, 0, 12, 9, 1, MODE_SMA, STO_LOWHIGH, MODE_MAIN, 2);
   double ind0val3  = iStochastic(NULL, 0, 12, 9, 1, MODE_SMA, STO_LOWHIGH, MODE_MAIN, 3);
   bool   ind0long  = ind0val1 < ind0val2 - sigma && ind0val2 > ind0val3 + sigma;
   bool   ind0short = ind0val1 > ind0val2 + sigma && ind0val2 < ind0val3 - sigma;
   // ADX (26), Level: 21.0
   double ind1val1  = iADX(NULL, 0, 26, PRICE_CLOSE, 0, 1);
   bool   ind1long  = ind1val1 < 21.0 - sigma;
   bool   ind1short = ind1long;

   return CreateEntrySignal(12, ind0long && ind1long, ind0short && ind1short, 22, 699, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_012()
  {
   // Commodity Channel Index (Typical, 46)
   double ind2val1  = iCCI(NULL, 0, 46, PRICE_TYPICAL, 1);
   double ind2val2  = iCCI(NULL, 0, 46, PRICE_TYPICAL, 2);
   bool   ind2long  = ind2val1 > ind2val2 + sigma;
   bool   ind2short = ind2val1 < ind2val2 - sigma;

   return CreateExitSignal(12, ind2long, ind2short, 22, 699, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_013()
  {
   // Directional Indicators (14)
   double ind0val1  = iADX(NULL, 0, 14, PRICE_CLOSE, 1, 1);
   double ind0val2  = iADX(NULL ,0 ,14, PRICE_CLOSE, 2, 1);
   double ind0val3  = iADX(NULL, 0, 14, PRICE_CLOSE, 1, 2);
   double ind0val4  = iADX(NULL ,0 ,14, PRICE_CLOSE, 2, 2);
   bool   ind0long  = ind0val1 < ind0val2 - sigma && ind0val3 > ind0val4 + sigma;
   bool   ind0short = ind0val1 > ind0val2 + sigma && ind0val3 < ind0val4 - sigma;
   // Stochastic (12, 7, 9)
   double ind1val1  = iStochastic(NULL, 0, 12, 7, 9, MODE_SMA, STO_LOWHIGH, MODE_MAIN, 1);
   double ind1val2  = iStochastic(NULL, 0, 12, 7, 9, MODE_SMA, STO_LOWHIGH, MODE_MAIN, 2);
   bool   ind1long  = ind1val1 > ind1val2 + sigma;
   bool   ind1short = ind1val1 < ind1val2 - sigma;
   // On Balance Volume
   double ind2val1  = iOBV(NULL, 0, PRICE_CLOSE, 1);
   double ind2val2  = iOBV(NULL, 0, PRICE_CLOSE, 2);
   bool   ind2long  = ind2val1 > ind2val2 + sigma;
   bool   ind2short = ind2val1 < ind2val2 - sigma;

   return CreateEntrySignal(13, ind0long && ind1long && ind2long, ind0short && ind1short && ind2short, 14, 702, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_013()
  {
   // DeMarker (40)
   double ind3val1  = iDeMarker(NULL, 0, 40, 1);
   double ind3val2  = iDeMarker(NULL, 0, 40, 2);
   bool   ind3long  = ind3val1 < ind3val2 - sigma;
   bool   ind3short = ind3val1 > ind3val2 + sigma;
   // Average True Range (29)
   double ind4val1  = iATR(NULL, 0, 29, 1);
   double ind4val2  = iATR(NULL, 0, 29, 2);
   bool   ind4long  = ind4val1 > ind4val2 + sigma;
   bool   ind4short = ind4long;

   return CreateExitSignal(13, ind3long || ind4long, ind3short || ind4short, 14, 702, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_014()
  {
   // Alligator (Exponential, Median, 36, 21, 21, 8, 8, 4)
   double ind0val1  = iAlligator(NULL, 0, 36, 21, 21, 8, 8, 4, MODE_EMA, PRICE_MEDIAN, MODE_GATORTEETH, 1);
   double ind0val2  = iAlligator(NULL, 0, 36, 21, 21, 8, 8, 4, MODE_EMA, PRICE_MEDIAN, MODE_GATORJAW,   1);
   double ind0val3  = iAlligator(NULL, 0, 36, 21, 21, 8, 8, 4, MODE_EMA, PRICE_MEDIAN, MODE_GATORTEETH, 2);
   double ind0val4  = iAlligator(NULL, 0, 36, 21, 21, 8, 8, 4, MODE_EMA, PRICE_MEDIAN, MODE_GATORJAW,   2);
   bool   ind0long  = ind0val1 > ind0val2 + sigma && ind0val3 < ind0val4 - sigma;
   bool   ind0short = ind0val1 < ind0val2 - sigma && ind0val3 > ind0val4 + sigma;

   return CreateEntrySignal(14, ind0long, ind0short, 22, 0, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_014()
  {
   // Alligator (Smoothed, Median, 41, 15, 15, 2, 2, 1)
   double ind1val1  = iAlligator(NULL, 0, 41, 15, 15, 2, 2, 1, MODE_SMMA, PRICE_MEDIAN, MODE_GATORLIPS,  1);
   double ind1val2  = iAlligator(NULL, 0, 41, 15, 15, 2, 2, 1, MODE_SMMA, PRICE_MEDIAN, MODE_GATORTEETH, 1);
   double ind1val3  = iAlligator(NULL, 0, 41, 15, 15, 2, 2, 1, MODE_SMMA, PRICE_MEDIAN, MODE_GATORLIPS,  2);
   double ind1val4  = iAlligator(NULL, 0, 41, 15, 15, 2, 2, 1, MODE_SMMA, PRICE_MEDIAN, MODE_GATORTEETH, 2);
   bool   ind1long  = ind1val1 > ind1val2 + sigma && ind1val3 < ind1val4 - sigma;
   bool   ind1short = ind1val1 < ind1val2 - sigma && ind1val3 > ind1val4 + sigma;

   return CreateExitSignal(14, ind1long, ind1short, 22, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_015()
  {
   // Momentum (Close, 22), Level: 100.0000
   double ind0val1  = iMomentum(NULL, 0, 22, PRICE_CLOSE, 1);
   double ind0val2  = iMomentum(NULL, 0, 22, PRICE_CLOSE, 2);
   bool   ind0long  = ind0val1 < 100.0000 - sigma && ind0val2 > 100.0000 + sigma;
   bool   ind0short = ind0val1 > 200 - 100.0000 + sigma && ind0val2 < 200 - 100.0000 - sigma;

   return CreateEntrySignal(15, ind0long, ind0short, 22, 0, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_015()
  {
   // Alligator (Smoothed, Median, 42, 17, 17, 8, 8, 1)
   double ind1val1  = iAlligator(NULL, 0, 42, 17, 17, 8, 8, 1, MODE_SMMA, PRICE_MEDIAN, MODE_GATORJAW,   1);
   double ind1val2  = iAlligator(NULL, 0, 42, 17, 17, 8, 8, 1, MODE_SMMA, PRICE_MEDIAN, MODE_GATORJAW,   2);
   bool   ind1long  = ind1val1 > ind1val2 + sigma;
   bool   ind1short = ind1val1 < ind1val2 - sigma;
   // Awesome Oscillator, Level: 0.0009
   double ind2val1  = iAO(NULL, 0, 1);
   bool   ind2long  = ind2val1 > 0.0009 + sigma;
   bool   ind2short = ind2val1 < -0.0009 - sigma;

   return CreateExitSignal(15, ind1long || ind2long, ind1short || ind2short, 22, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_016()
  {
   // RSI (Close, 10), Level: 63
   double ind0val1  = iRSI(NULL, 0, 10, PRICE_CLOSE, 1);
   double ind0val2  = iRSI(NULL, 0, 10, PRICE_CLOSE, 2);
   bool   ind0long  = ind0val1 < 63 - sigma && ind0val2 > 63 + sigma;
   bool   ind0short = ind0val1 > 100 - 63 + sigma && ind0val2 < 100 - 63 - sigma;
   // Average True Range (5)
   double ind1val1  = iATR(NULL, 0, 5, 1);
   double ind1val2  = iATR(NULL, 0, 5, 2);
   bool   ind1long  = ind1val1 > ind1val2 + sigma;
   bool   ind1short = ind1long;

   return CreateEntrySignal(16, ind0long && ind1long, ind0short && ind1short, 23, 0, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_016()
  {
   // Bollinger Bands (Close, 29, 3.60)
   double ind2upBand1 = iBands(NULL, 0, 29, 3.60, 0, PRICE_CLOSE, MODE_UPPER, 1);
   double ind2dnBand1 = iBands(NULL, 0, 29, 3.60, 0, PRICE_CLOSE, MODE_LOWER, 1);
   double ind2upBand2 = iBands(NULL, 0, 29, 3.60, 0, PRICE_CLOSE, MODE_UPPER, 2);
   double ind2dnBand2 = iBands(NULL, 0, 29, 3.60, 0, PRICE_CLOSE, MODE_LOWER, 2);
   bool   ind2long    = Open(0) < ind2upBand1 - sigma && Open(1) > ind2upBand2 + sigma;
   bool   ind2short   = Open(0) > ind2dnBand1 + sigma && Open(1) < ind2dnBand2 - sigma;
   // Momentum (Close, 29)
   double ind3val1  = iMomentum(NULL, 0, 29, PRICE_CLOSE, 1);
   double ind3val2  = iMomentum(NULL, 0, 29, PRICE_CLOSE, 2);
   bool   ind3long  = ind3val1 < ind3val2 - sigma;
   bool   ind3short = ind3val1 > ind3val2 + sigma;

   return CreateExitSignal(16, ind2long || ind3long, ind2short || ind3short, 23, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_017()
  {
   // Awesome Oscillator, Level: 0.0000
   double ind0val1  = iAO(NULL, 0, 1);
   double ind0val2  = iAO(NULL, 0, 2);
   bool   ind0long  = ind0val1 > 0.0000 + sigma && ind0val2 < 0.0000 - sigma;
   bool   ind0short = ind0val1 < 0.0000 - sigma && ind0val2 > 0.0000 + sigma;

   return CreateEntrySignal(17, ind0long, ind0short, 20, 551, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_017()
  {
   // Commodity Channel Index (Typical, 17)
   double ind1val1  = iCCI(NULL, 0, 17, PRICE_TYPICAL, 1);
   double ind1val2  = iCCI(NULL, 0, 17, PRICE_TYPICAL, 2);
   bool   ind1long  = ind1val1 > ind1val2 + sigma;
   bool   ind1short = ind1val1 < ind1val2 - sigma;
   // ADX (43)
   double ind2val1  = iADX(NULL, 0, 43, PRICE_CLOSE, 0, 1);
   double ind2val2  = iADX(NULL, 0, 43, PRICE_CLOSE, 0, 2);
   double ind2val3  = iADX(NULL, 0, 43, PRICE_CLOSE, 0, 3);
   bool   ind2long  = ind2val1 > ind2val2 + sigma && ind2val2 < ind2val3 - sigma;
   bool   ind2short = ind2long;
   // Alligator (Smoothed, Median, 41, 20, 20, 12, 12, 3)
   double ind3val1  = iAlligator(NULL, 0, 41, 20, 20, 12, 12, 3, MODE_SMMA, PRICE_MEDIAN, MODE_GATORJAW,   1);
   double ind3val2  = iAlligator(NULL, 0, 41, 20, 20, 12, 12, 3, MODE_SMMA, PRICE_MEDIAN, MODE_GATORJAW,   2);
   bool   ind3long  = ind3val1 < ind3val2 - sigma;
   bool   ind3short = ind3val1 > ind3val2 + sigma;

   return CreateExitSignal(17, ind1long || ind2long || ind3long, ind1short || ind2short || ind3short, 20, 551, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_018()
  {
   // Moving Average (Exponential, Close, 26, 0)
   double ind0val1  = iMA(NULL, 0, 26, 0, MODE_EMA, PRICE_CLOSE, 1);
   double ind0val2  = iMA(NULL, 0, 26, 0, MODE_EMA, PRICE_CLOSE, 2);
   bool   ind0long  = Open(0) < ind0val1 - sigma && Open(1) > ind0val2 + sigma;
   bool   ind0short = Open(0) > ind0val1 + sigma && Open(1) < ind0val2 - sigma;
   // Alligator (Weighted, Median, 17, 14, 14, 9, 9, 2)
   double ind1val1  = iAlligator(NULL, 0, 17, 14, 14, 9, 9, 2, MODE_LWMA, PRICE_MEDIAN, MODE_GATORTEETH, 1);
   double ind1val2  = iAlligator(NULL, 0, 17, 14, 14, 9, 9, 2, MODE_LWMA, PRICE_MEDIAN, MODE_GATORTEETH, 2);
   bool   ind1long  = ind1val1 < ind1val2 - sigma;
   bool   ind1short = ind1val1 > ind1val2 + sigma;

   return CreateEntrySignal(18, ind0long && ind1long, ind0short && ind1short, 12, 989, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_018()
  {
   // DeMarker (9), Level: 0.54
   double ind2val1  = iDeMarker(NULL, 0, 9, 1);
   bool   ind2long  = ind2val1 > 0.54 + sigma;
   bool   ind2short = ind2val1 < 1 - 0.54 - sigma;

   return CreateExitSignal(18, ind2long, ind2short, 12, 989, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_019()
  {
   // Alligator (Exponential, Median, 35, 23, 23, 7, 7, 2)
   double ind0val1  = iAlligator(NULL, 0, 35, 23, 23, 7, 7, 2, MODE_EMA, PRICE_MEDIAN, MODE_GATORTEETH, 1);
   double ind0val2  = iAlligator(NULL, 0, 35, 23, 23, 7, 7, 2, MODE_EMA, PRICE_MEDIAN, MODE_GATORJAW,   1);
   double ind0val3  = iAlligator(NULL, 0, 35, 23, 23, 7, 7, 2, MODE_EMA, PRICE_MEDIAN, MODE_GATORTEETH, 2);
   double ind0val4  = iAlligator(NULL, 0, 35, 23, 23, 7, 7, 2, MODE_EMA, PRICE_MEDIAN, MODE_GATORJAW,   2);
   bool   ind0long  = ind0val1 > ind0val2 + sigma && ind0val3 < ind0val4 - sigma;
   bool   ind0short = ind0val1 < ind0val2 - sigma && ind0val3 > ind0val4 + sigma;

   return CreateEntrySignal(19, ind0long, ind0short, 13, 54, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_019()
  {
   // Alligator (Smoothed, Median, 32, 25, 25, 11, 11, 5)
   double ind1val1  = iAlligator(NULL, 0, 32, 25, 25, 11, 11, 5, MODE_SMMA, PRICE_MEDIAN, MODE_GATORLIPS,  1);
   double ind1val2  = iAlligator(NULL, 0, 32, 25, 25, 11, 11, 5, MODE_SMMA, PRICE_MEDIAN, MODE_GATORJAW,   1);
   double ind1val3  = iAlligator(NULL, 0, 32, 25, 25, 11, 11, 5, MODE_SMMA, PRICE_MEDIAN, MODE_GATORLIPS,  2);
   double ind1val4  = iAlligator(NULL, 0, 32, 25, 25, 11, 11, 5, MODE_SMMA, PRICE_MEDIAN, MODE_GATORJAW,   2);
   bool   ind1long  = ind1val1 < ind1val2 - sigma && ind1val3 > ind1val4 + sigma;
   bool   ind1short = ind1val1 > ind1val2 + sigma && ind1val3 < ind1val4 - sigma;
   // ADX (45)
   double ind2val1  = iADX(NULL, 0, 45, PRICE_CLOSE, 0, 1);
   double ind2val2  = iADX(NULL, 0, 45, PRICE_CLOSE, 0, 2);
   double ind2val3  = iADX(NULL, 0, 45, PRICE_CLOSE, 0, 3);
   bool   ind2long  = ind2val1 > ind2val2 + sigma && ind2val2 < ind2val3 - sigma;
   bool   ind2short = ind2long;

   return CreateExitSignal(19, ind1long || ind2long, ind1short || ind2short, 13, 54, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_020()
  {
   // Momentum (Close, 22), Level: 100.0000
   double ind0val1  = iMomentum(NULL, 0, 22, PRICE_CLOSE, 1);
   double ind0val2  = iMomentum(NULL, 0, 22, PRICE_CLOSE, 2);
   bool   ind0long  = ind0val1 < 100.0000 - sigma && ind0val2 > 100.0000 + sigma;
   bool   ind0short = ind0val1 > 200 - 100.0000 + sigma && ind0val2 < 200 - 100.0000 - sigma;

   return CreateEntrySignal(20, ind0long, ind0short, 26, 0, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_020()
  {
   // Moving Average (Simple, Close, 15, 3)
   double ind1val1  = iMA(NULL, 0, 15, 3, MODE_SMA, PRICE_CLOSE, 1);
   double ind1val2  = iMA(NULL, 0, 15, 3, MODE_SMA, PRICE_CLOSE, 2);
   bool   ind1long  = ind1val1 > ind1val2 + sigma;
   bool   ind1short = ind1val1 < ind1val2 - sigma;

   return CreateExitSignal(20, ind1long, ind1short, 26, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_021()
  {
   // Directional Indicators (19)
   double ind0val1  = iADX(NULL, 0, 19, PRICE_CLOSE, 1, 1);
   double ind0val2  = iADX(NULL ,0 ,19, PRICE_CLOSE, 2, 1);
   double ind0val3  = iADX(NULL, 0, 19, PRICE_CLOSE, 1, 2);
   double ind0val4  = iADX(NULL ,0 ,19, PRICE_CLOSE, 2, 2);
   bool   ind0long  = ind0val1 < ind0val2 - sigma && ind0val3 > ind0val4 + sigma;
   bool   ind0short = ind0val1 > ind0val2 + sigma && ind0val3 < ind0val4 - sigma;

   return CreateEntrySignal(21, ind0long, ind0short, 26, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_021()
  {
   // Average True Range (46)
   double ind1val1  = iATR(NULL, 0, 46, 1);
   double ind1val2  = iATR(NULL, 0, 46, 2);
   bool   ind1long  = ind1val1 < ind1val2 - sigma;
   bool   ind1short = ind1long;
   // Envelopes (Close, Simple, 28, 0.44)
   double ind2upBand1 = iEnvelopes(NULL, 0, 28, MODE_SMA, 0, PRICE_CLOSE, 0.44, MODE_UPPER, 1);
   double ind2dnBand1 = iEnvelopes(NULL, 0, 28, MODE_SMA, 0, PRICE_CLOSE, 0.44, MODE_LOWER, 1);
   double ind2upBand2 = iEnvelopes(NULL, 0, 28, MODE_SMA, 0, PRICE_CLOSE, 0.44, MODE_UPPER, 2);
   double ind2dnBand2 = iEnvelopes(NULL, 0, 28, MODE_SMA, 0, PRICE_CLOSE, 0.44, MODE_LOWER, 2);
   bool   ind2long    = Open(0) < ind2upBand1 - sigma && Open(1) > ind2upBand2 + sigma;
   bool   ind2short   = Open(0) > ind2dnBand1 + sigma && Open(1) < ind2dnBand2 - sigma;

   return CreateExitSignal(21, ind1long || ind2long, ind1short || ind2short, 26, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_022()
  {
   // Awesome Oscillator
   double ind0val1  = iAO(NULL, 0, 1);
   double ind0val2  = iAO(NULL, 0, 2);
   bool   ind0long  = ind0val1 < ind0val2 - sigma;
   bool   ind0short = ind0val1 > ind0val2 + sigma;
   // Envelopes (Close, Simple, 15, 0.07)
   double ind1upBand1 = iEnvelopes(NULL, 0, 15, MODE_SMA, 0, PRICE_CLOSE, 0.07, MODE_UPPER, 1);
   double ind1dnBand1 = iEnvelopes(NULL, 0, 15, MODE_SMA, 0, PRICE_CLOSE, 0.07, MODE_LOWER, 1);
   double ind1upBand2 = iEnvelopes(NULL, 0, 15, MODE_SMA, 0, PRICE_CLOSE, 0.07, MODE_UPPER, 2);
   double ind1dnBand2 = iEnvelopes(NULL, 0, 15, MODE_SMA, 0, PRICE_CLOSE, 0.07, MODE_LOWER, 2);
   bool   ind1long    = Open(0) < ind1upBand1 - sigma && Open(1) > ind1upBand2 + sigma;
   bool   ind1short   = Open(0) > ind1dnBand1 + sigma && Open(1) < ind1dnBand2 - sigma;

   return CreateEntrySignal(22, ind0long && ind1long, ind0short && ind1short, 21, 670, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_022()
  {
   // Moving Average (Simple, Close, 39, 0)
   double ind2val1  = iMA(NULL, 0, 39, 0, MODE_SMA, PRICE_CLOSE, 1);
   bool   ind2long  = Open(0) > ind2val1 + sigma;
   bool   ind2short = Open(0) < ind2val1 - sigma;

   return CreateExitSignal(22, ind2long, ind2short, 21, 670, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_023()
  {
   // MACD Signal (Close, 14, 49, 3)
   double ind0val1  = iMACD(NULL, 0, 14, 49, 3, PRICE_CLOSE, MODE_MAIN, 1) - iMACD(NULL, 0, 14, 49, 3, PRICE_CLOSE ,MODE_SIGNAL, 1);
   double ind0val2  = iMACD(NULL, 0, 14, 49, 3, PRICE_CLOSE, MODE_MAIN, 2) - iMACD(NULL, 0, 14, 49, 3, PRICE_CLOSE ,MODE_SIGNAL, 2);
   bool   ind0long  = ind0val1 < 0 - sigma && ind0val2 > 0 + sigma;
   bool   ind0short = ind0val1 > 0 + sigma && ind0val2 < 0 - sigma;

   return CreateEntrySignal(23, ind0long, ind0short, 22, 429, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_023()
  {
   // Average True Range (34), Level: 0.0017
   double ind1val1  = iATR(NULL, 0, 34, 1);
   bool   ind1long  = ind1val1 < 0.0017 - sigma;
   bool   ind1short = ind1long;
   // Awesome Oscillator
   double ind2val1  = iAO(NULL, 0, 1);
   double ind2val2  = iAO(NULL, 0, 2);
   bool   ind2long  = ind2val1 > ind2val2 + sigma;
   bool   ind2short = ind2val1 < ind2val2 - sigma;

   return CreateExitSignal(23, ind1long || ind2long, ind1short || ind2short, 22, 429, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_024()
  {
   // Moving Average (Simple, Close, 7, 5)
   double ind0val1  = iMA(NULL, 0, 7, 5, MODE_SMA, PRICE_CLOSE, 1);
   bool   ind0long  = Open(0) < ind0val1 - sigma;
   bool   ind0short = Open(0) > ind0val1 + sigma;
   // MACD Signal (Close, 17, 45, 3)
   double ind1val1  = iMACD(NULL, 0, 17, 45, 3, PRICE_CLOSE, MODE_MAIN, 1) - iMACD(NULL, 0, 17, 45, 3, PRICE_CLOSE ,MODE_SIGNAL, 1);
   double ind1val2  = iMACD(NULL, 0, 17, 45, 3, PRICE_CLOSE, MODE_MAIN, 2) - iMACD(NULL, 0, 17, 45, 3, PRICE_CLOSE ,MODE_SIGNAL, 2);
   bool   ind1long  = ind1val1 < 0 - sigma && ind1val2 > 0 + sigma;
   bool   ind1short = ind1val1 > 0 + sigma && ind1val2 < 0 - sigma;

   return CreateEntrySignal(24, ind0long && ind1long, ind0short && ind1short, 12, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_024()
  {
   // Stochastic (15, 1, 11)
   double ind2val1  = iStochastic(NULL, 0, 15, 1, 11, MODE_SMA, STO_LOWHIGH, MODE_MAIN, 1);
   double ind2val2  = iStochastic(NULL, 0, 15, 1, 11, MODE_SMA, STO_LOWHIGH, MODE_MAIN, 2);
   bool   ind2long  = ind2val1 > ind2val2 + sigma;
   bool   ind2short = ind2val1 < ind2val2 - sigma;
   // Williams' Percent Range (15), Level: -26.0
   double ind3val1  = iWPR(NULL, 0, 15, 1);
   bool   ind3long  = ind3val1 > -26.0 + sigma;
   bool   ind3short = ind3val1 < -100 - -26.0 - sigma;
   // Alligator (Weighted, Median, 17, 11, 11, 2, 2, 1)
   double ind4val1  = iAlligator(NULL, 0, 17, 11, 11, 2, 2, 1, MODE_LWMA, PRICE_MEDIAN, MODE_GATORTEETH, 1);
   double ind4val2  = iAlligator(NULL, 0, 17, 11, 11, 2, 2, 1, MODE_LWMA, PRICE_MEDIAN, MODE_GATORTEETH, 2);
   bool   ind4long  = ind4val1 < ind4val2 - sigma;
   bool   ind4short = ind4val1 > ind4val2 + sigma;

   return CreateExitSignal(24, ind2long || ind3long || ind4long, ind2short || ind3short || ind4short, 12, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_025()
  {
   // Stochastic (11, 8, 10), Level: 20.0
   double ind0val1  = iStochastic(NULL, 0, 11, 8, 10, MODE_SMA, STO_LOWHIGH, MODE_MAIN, 1);
   double ind0val2  = iStochastic(NULL, 0, 11, 8, 10, MODE_SMA, STO_LOWHIGH, MODE_MAIN, 2);
   bool   ind0long  = ind0val1 < 20.0 - sigma && ind0val2 > 20.0 + sigma;
   bool   ind0short = ind0val1 > 100 - 20.0 + sigma && ind0val2 < 100 - 20.0 - sigma;

   return CreateEntrySignal(25, ind0long, ind0short, 15, 217, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_025()
  {
   // Stochastic (15, 12, 13), Level: 39.0
   double ind1val1  = iStochastic(NULL, 0, 15, 12, 13, MODE_SMA, STO_LOWHIGH, MODE_MAIN, 1);
   bool   ind1long  = ind1val1 < 39.0 - sigma;
   bool   ind1short = ind1val1 > 100 - 39.0 + sigma;
   // Momentum (Close, 29)
   double ind2val1  = iMomentum(NULL, 0, 29, PRICE_CLOSE, 1);
   double ind2val2  = iMomentum(NULL, 0, 29, PRICE_CLOSE, 2);
   double ind2val3  = iMomentum(NULL, 0, 29, PRICE_CLOSE, 3);
   bool   ind2long  = ind2val1 < ind2val2 - sigma && ind2val2 > ind2val3 + sigma;
   bool   ind2short = ind2val1 > ind2val2 + sigma && ind2val2 < ind2val3 - sigma;

   return CreateExitSignal(25, ind1long || ind2long, ind1short || ind2short, 15, 217, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_026()
  {
   // Moving Average (Simple, Close, 13, 0)
   double ind0val1  = iMA(NULL, 0, 13, 0, MODE_SMA, PRICE_CLOSE, 1);
   double ind0val2  = iMA(NULL, 0, 13, 0, MODE_SMA, PRICE_CLOSE, 2);
   bool   ind0long  = Open(0) < ind0val1 - sigma && Open(1) > ind0val2 + sigma;
   bool   ind0short = Open(0) > ind0val1 + sigma && Open(1) < ind0val2 - sigma;

   return CreateEntrySignal(26, ind0long, ind0short, 20, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_026()
  {
   // Momentum (Close, 7)
   double ind1val1  = iMomentum(NULL, 0, 7, PRICE_CLOSE, 1);
   double ind1val2  = iMomentum(NULL, 0, 7, PRICE_CLOSE, 2);
   bool   ind1long  = ind1val1 < ind1val2 - sigma;
   bool   ind1short = ind1val1 > ind1val2 + sigma;

   return CreateExitSignal(26, ind1long, ind1short, 20, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_027()
  {
   // MACD Signal (Close, 20, 43, 4)
   double ind0val1  = iMACD(NULL, 0, 20, 43, 4, PRICE_CLOSE, MODE_MAIN, 1) - iMACD(NULL, 0, 20, 43, 4, PRICE_CLOSE ,MODE_SIGNAL, 1);
   double ind0val2  = iMACD(NULL, 0, 20, 43, 4, PRICE_CLOSE, MODE_MAIN, 2) - iMACD(NULL, 0, 20, 43, 4, PRICE_CLOSE ,MODE_SIGNAL, 2);
   bool   ind0long  = ind0val1 < 0 - sigma && ind0val2 > 0 + sigma;
   bool   ind0short = ind0val1 > 0 + sigma && ind0val2 < 0 - sigma;
   // Stochastic Signal (10, 5, 4)
   double ind1val1  = iStochastic(NULL, 0, 10, 5, 4, MODE_SMA, 0, MODE_MAIN,   1);
   double ind1val2  = iStochastic(NULL, 0, 10, 5, 4, MODE_SMA, 0, MODE_SIGNAL, 1);
   bool   ind1long  = ind1val1 < ind1val2 - sigma;
   bool   ind1short = ind1val1 > ind1val2 + sigma;
   // Momentum (Close, 38), Level: 100.0000
   double ind2val1  = iMomentum(NULL, 0, 38, PRICE_CLOSE, 1);
   bool   ind2long  = ind2val1 > 100.0000 + sigma;
   bool   ind2short = ind2val1 < 200 - 100.0000 - sigma;

   return CreateEntrySignal(27, ind0long && ind1long && ind2long, ind0short && ind1short && ind2short, 17, 528, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_027()
  {
   // Stochastic Signal (12, 5, 4)
   double ind3val1  = iStochastic(NULL, 0, 12, 5, 4, MODE_SMA, 0, MODE_MAIN,   1);
   double ind3val2  = iStochastic(NULL, 0, 12, 5, 4, MODE_SMA, 0, MODE_SIGNAL, 1);
   bool   ind3long  = ind3val1 < ind3val2 - sigma;
   bool   ind3short = ind3val1 > ind3val2 + sigma;
   // Momentum (Close, 27)
   double ind4val1  = iMomentum(NULL, 0, 27, PRICE_CLOSE, 1);
   double ind4val2  = iMomentum(NULL, 0, 27, PRICE_CLOSE, 2);
   double ind4val3  = iMomentum(NULL, 0, 27, PRICE_CLOSE, 3);
   bool   ind4long  = ind4val1 < ind4val2 - sigma && ind4val2 > ind4val3 + sigma;
   bool   ind4short = ind4val1 > ind4val2 + sigma && ind4val2 < ind4val3 - sigma;
   // Momentum (Close, 42), Level: 99.0000
   double ind5val1  = iMomentum(NULL, 0, 42, PRICE_CLOSE, 1);
   double ind5val2  = iMomentum(NULL, 0, 42, PRICE_CLOSE, 2);
   bool   ind5long  = ind5val1 < 99.0000 - sigma && ind5val2 > 99.0000 + sigma;
   bool   ind5short = ind5val1 > 200 - 99.0000 + sigma && ind5val2 < 200 - 99.0000 - sigma;

   return CreateExitSignal(27, ind3long || ind4long || ind5long, ind3short || ind4short || ind5short, 17, 528, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_028()
  {
   // Envelopes (Close, Simple, 28, 0.22)
   double ind0upBand1 = iEnvelopes(NULL, 0, 28, MODE_SMA, 0, PRICE_CLOSE, 0.22, MODE_UPPER, 1);
   double ind0dnBand1 = iEnvelopes(NULL, 0, 28, MODE_SMA, 0, PRICE_CLOSE, 0.22, MODE_LOWER, 1);
   double ind0upBand2 = iEnvelopes(NULL, 0, 28, MODE_SMA, 0, PRICE_CLOSE, 0.22, MODE_UPPER, 2);
   double ind0dnBand2 = iEnvelopes(NULL, 0, 28, MODE_SMA, 0, PRICE_CLOSE, 0.22, MODE_LOWER, 2);
   bool   ind0long    = Open(0) < ind0dnBand1 - sigma && Open(1) > ind0dnBand2 + sigma;
   bool   ind0short   = Open(0) > ind0upBand1 + sigma && Open(1) < ind0upBand2 - sigma;

   return CreateEntrySignal(28, ind0long, ind0short, 26, 983, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_028()
  {
   // RSI (Close, 35), Level: 72
   double ind1val1  = iRSI(NULL, 0, 35, PRICE_CLOSE, 1);
   bool   ind1long  = ind1val1 > 72 + sigma;
   bool   ind1short = ind1val1 < 100 - 72 - sigma;
   // Awesome Oscillator, Level: 0.0000
   double ind2val1  = iAO(NULL, 0, 1);
   double ind2val2  = iAO(NULL, 0, 2);
   bool   ind2long  = ind2val1 > 0.0000 + sigma && ind2val2 < 0.0000 - sigma;
   bool   ind2short = ind2val1 < 0.0000 - sigma && ind2val2 > 0.0000 + sigma;
   // RSI (Close, 40)
   double ind3val1  = iRSI(NULL, 0, 40, PRICE_CLOSE, 1);
   double ind3val2  = iRSI(NULL, 0, 40, PRICE_CLOSE, 2);
   bool   ind3long  = ind3val1 < ind3val2 - sigma;
   bool   ind3short = ind3val1 > ind3val2 + sigma;

   return CreateExitSignal(28, ind1long || ind2long || ind3long, ind1short || ind2short || ind3short, 26, 983, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_029()
  {
   // Momentum (Close, 27), Level: 100.0000
   double ind0val1  = iMomentum(NULL, 0, 27, PRICE_CLOSE, 1);
   double ind0val2  = iMomentum(NULL, 0, 27, PRICE_CLOSE, 2);
   bool   ind0long  = ind0val1 < 100.0000 - sigma && ind0val2 > 100.0000 + sigma;
   bool   ind0short = ind0val1 > 200 - 100.0000 + sigma && ind0val2 < 200 - 100.0000 - sigma;

   return CreateEntrySignal(29, ind0long, ind0short, 14, 0, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_029()
  {
   // Standard Deviation (Close, Simple, 48), Level: 0.0029
   double ind1val1  = iStdDev(NULL , 0, 48, 0, MODE_SMA, PRICE_CLOSE, 1);
   bool   ind1long  = ind1val1 < 0.0029 - sigma;
   bool   ind1short = ind1long;

   return CreateExitSignal(29, ind1long, ind1short, 14, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_030()
  {
   // Directional Indicators (20)
   double ind0val1  = iADX(NULL, 0, 20, PRICE_CLOSE, 1, 1);
   double ind0val2  = iADX(NULL ,0 ,20, PRICE_CLOSE, 2, 1);
   double ind0val3  = iADX(NULL, 0, 20, PRICE_CLOSE, 1, 2);
   double ind0val4  = iADX(NULL ,0 ,20, PRICE_CLOSE, 2, 2);
   bool   ind0long  = ind0val1 < ind0val2 - sigma && ind0val3 > ind0val4 + sigma;
   bool   ind0short = ind0val1 > ind0val2 + sigma && ind0val3 < ind0val4 - sigma;

   return CreateEntrySignal(30, ind0long, ind0short, 18, 0, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_030()
  {
   // ADX (13), Level: 22.0
   double ind1val1  = iADX(NULL, 0, 13, PRICE_CLOSE, 0, 1);
   bool   ind1long  = ind1val1 < 22.0 - sigma;
   bool   ind1short = ind1long;
   // Momentum (Close, 12), Level: 100.0000
   double ind2val1  = iMomentum(NULL, 0, 12, PRICE_CLOSE, 1);
   bool   ind2long  = ind2val1 > 100.0000 + sigma;
   bool   ind2short = ind2val1 < 200 - 100.0000 - sigma;
   // Moving Average (Simple, Close, 27, 10)
   double ind3val1  = iMA(NULL, 0, 27, 10, MODE_SMA, PRICE_CLOSE, 1);
   double ind3val2  = iMA(NULL, 0, 27, 10, MODE_SMA, PRICE_CLOSE, 2);
   double ind3val3  = iMA(NULL, 0, 27, 10, MODE_SMA, PRICE_CLOSE, 3);
   bool   ind3long  = ind3val1 > ind3val2 + sigma && ind3val2 < ind3val3 - sigma;
   bool   ind3short = ind3val1 < ind3val2 - sigma && ind3val2 > ind3val3 + sigma;

   return CreateExitSignal(30, ind1long || ind2long || ind3long, ind1short || ind2short || ind3short, 18, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_031()
  {
   // Moving Averages Crossover (Simple, Simple, 5, 36)
   double ind0val1  = iMA(NULL, 0, 5, 0, MODE_SMA, PRICE_CLOSE, 1);
   double ind0val2  = iMA(NULL, 0, 36, 0, MODE_SMA, PRICE_CLOSE, 1);
   double ind0val3  = iMA(NULL, 0, 5, 0, MODE_SMA, PRICE_CLOSE, 2);
   double ind0val4  = iMA(NULL, 0, 36, 0, MODE_SMA, PRICE_CLOSE, 2);
   bool   ind0long  = ind0val1 > ind0val2 + sigma && ind0val3 < ind0val4 - sigma;
   bool   ind0short = ind0val1 < ind0val2 - sigma && ind0val3 > ind0val4 + sigma;

   return CreateEntrySignal(31, ind0long, ind0short, 12, 0, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_031()
  {
   // Moving Average (Simple, Close, 34, 6)
   double ind1val1  = iMA(NULL, 0, 34, 6, MODE_SMA, PRICE_CLOSE, 1);
   double ind1val2  = iMA(NULL, 0, 34, 6, MODE_SMA, PRICE_CLOSE, 2);
   bool   ind1long  = ind1val1 < ind1val2 - sigma;
   bool   ind1short = ind1val1 > ind1val2 + sigma;

   return CreateExitSignal(31, ind1long, ind1short, 12, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_032()
  {
   // On Balance Volume
   double ind0val1  = iOBV(NULL, 0, PRICE_CLOSE, 1);
   double ind0val2  = iOBV(NULL, 0, PRICE_CLOSE, 2);
   double ind0val3  = iOBV(NULL, 0, PRICE_CLOSE, 3);
   bool   ind0long  = ind0val1 < ind0val2 - sigma && ind0val2 > ind0val3 + sigma;
   bool   ind0short = ind0val1 > ind0val2 + sigma && ind0val2 < ind0val3 - sigma;

   return CreateEntrySignal(32, ind0long, ind0short, 21, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_032()
  {
   // Directional Indicators (11)
   double ind1val1  = iADX(NULL, 0, 11, PRICE_CLOSE, 1, 1);
   double ind1val2  = iADX(NULL ,0 ,11, PRICE_CLOSE, 2, 1);
   bool   ind1long  = ind1val1 > ind1val2 + sigma;
   bool   ind1short = ind1val1 < ind1val2 - sigma;
   // RSI (Close, 49), Level: 62
   double ind2val1  = iRSI(NULL, 0, 49, PRICE_CLOSE, 1);
   bool   ind2long  = ind2val1 > 62 + sigma;
   bool   ind2short = ind2val1 < 100 - 62 - sigma;

   return CreateExitSignal(32, ind1long || ind2long, ind1short || ind2short, 21, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_033()
  {
   // Stochastic Signal (4, 2, 2)
   double ind0val1  = iStochastic(NULL, 0, 4, 2, 2, MODE_SMA, 0, MODE_MAIN,   1);
   double ind0val2  = iStochastic(NULL, 0, 4, 2, 2, MODE_SMA, 0, MODE_SIGNAL, 1);
   double ind0val3  = iStochastic(NULL, 0, 4, 2, 2, MODE_SMA, 0, MODE_MAIN,   2);
   double ind0val4  = iStochastic(NULL, 0, 4, 2, 2, MODE_SMA, 0, MODE_SIGNAL, 2);
   bool   ind0long  = ind0val1 < ind0val2 - sigma && ind0val3 > ind0val4 + sigma;
   bool   ind0short = ind0val1 > ind0val2 + sigma && ind0val3 < ind0val4 - sigma;
   // Momentum (Close, 28)
   double ind1val1  = iMomentum(NULL, 0, 28, PRICE_CLOSE, 1);
   double ind1val2  = iMomentum(NULL, 0, 28, PRICE_CLOSE, 2);
   double ind1val3  = iMomentum(NULL, 0, 28, PRICE_CLOSE, 3);
   bool   ind1long  = ind1val1 < ind1val2 - sigma && ind1val2 > ind1val3 + sigma;
   bool   ind1short = ind1val1 > ind1val2 + sigma && ind1val2 < ind1val3 - sigma;
   // Momentum (Close, 32), Level: 100.0000
   double ind2val1  = iMomentum(NULL, 0, 32, PRICE_CLOSE, 1);
   bool   ind2long  = ind2val1 > 100.0000 + sigma;
   bool   ind2short = ind2val1 < 200 - 100.0000 - sigma;

   return CreateEntrySignal(33, ind0long && ind1long && ind2long, ind0short && ind1short && ind2short, 19, 0, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_033()
  {
   // Commodity Channel Index (Typical, 40), Level: 0
   double ind3val1  = iCCI(NULL, 0, 40, PRICE_TYPICAL, 1);
   bool   ind3long  = ind3val1 > 0 + sigma;
   bool   ind3short = ind3val1 < 0 - sigma;

   return CreateExitSignal(33, ind3long, ind3short, 19, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_034()
  {
   // Moving Average (Smoothed, Close, 44, 0)
   double ind0val1  = iMA(NULL, 0, 44, 0, MODE_SMMA, PRICE_CLOSE, 1);
   double ind0val2  = iMA(NULL, 0, 44, 0, MODE_SMMA, PRICE_CLOSE, 2);
   bool   ind0long  = Open(0) < ind0val1 - sigma && Open(1) > ind0val2 + sigma;
   bool   ind0short = Open(0) > ind0val1 + sigma && Open(1) < ind0val2 - sigma;

   return CreateEntrySignal(34, ind0long, ind0short, 20, 0, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_034()
  {
   // Commodity Channel Index (Typical, 19)
   double ind1val1  = iCCI(NULL, 0, 19, PRICE_TYPICAL, 1);
   double ind1val2  = iCCI(NULL, 0, 19, PRICE_TYPICAL, 2);
   bool   ind1long  = ind1val1 > ind1val2 + sigma;
   bool   ind1short = ind1val1 < ind1val2 - sigma;

   return CreateExitSignal(34, ind1long, ind1short, 20, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_035()
  {
   // Awesome Oscillator, Level: -0.0006
   double ind0val1  = iAO(NULL, 0, 1);
   double ind0val2  = iAO(NULL, 0, 2);
   bool   ind0long  = ind0val1 > -0.0006 + sigma && ind0val2 < -0.0006 - sigma;
   bool   ind0short = ind0val1 < 0.0006 - sigma && ind0val2 > 0.0006 + sigma;

   return CreateEntrySignal(35, ind0long, ind0short, 26, 0, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_035()
  {
   // Accelerator Oscillator
   double ind1val1  = iAC(NULL, 0, 1);
   double ind1val2  = iAC(NULL, 0, 2);
   bool   ind1long  = ind1val1 > ind1val2 + sigma;
   bool   ind1short = ind1val1 < ind1val2 - sigma;

   return CreateExitSignal(35, ind1long, ind1short, 26, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_036()
  {
   // Bollinger Bands (Close, 32, 2.63)
   double ind0upBand1 = iBands(NULL, 0, 32, 2.63, 0, PRICE_CLOSE, MODE_UPPER, 1);
   double ind0dnBand1 = iBands(NULL, 0, 32, 2.63, 0, PRICE_CLOSE, MODE_LOWER, 1);
   double ind0upBand2 = iBands(NULL, 0, 32, 2.63, 0, PRICE_CLOSE, MODE_UPPER, 2);
   double ind0dnBand2 = iBands(NULL, 0, 32, 2.63, 0, PRICE_CLOSE, MODE_LOWER, 2);
   bool   ind0long    = Open(0) < ind0upBand1 - sigma && Open(1) > ind0upBand2 + sigma;
   bool   ind0short   = Open(0) > ind0dnBand1 + sigma && Open(1) < ind0dnBand2 - sigma;
   // Moving Average (Simple, Close, 6, 0)
   double ind1val1  = iMA(NULL, 0, 6, 0, MODE_SMA, PRICE_CLOSE, 1);
   bool   ind1long  = Open(0) > ind1val1 + sigma;
   bool   ind1short = Open(0) < ind1val1 - sigma;

   return CreateEntrySignal(36, ind0long && ind1long, ind0short && ind1short, 24, 0, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_036()
  {
   // Bollinger Bands (Close, 22, 3.68)
   double ind2upBand1 = iBands(NULL, 0, 22, 3.68, 0, PRICE_CLOSE, MODE_UPPER, 1);
   double ind2dnBand1 = iBands(NULL, 0, 22, 3.68, 0, PRICE_CLOSE, MODE_LOWER, 1);
   bool   ind2long  = Open(0) < ind2dnBand1 - sigma;
   bool   ind2short = Open(0) > ind2upBand1 + sigma;

   return CreateExitSignal(36, ind2long, ind2short, 24, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_037()
  {
   // Commodity Channel Index (Typical, 17), Level: 0
   double ind0val1  = iCCI(NULL, 0, 17, PRICE_TYPICAL, 1);
   double ind0val2  = iCCI(NULL, 0, 17, PRICE_TYPICAL, 2);
   bool   ind0long  = ind0val1 < 0 - sigma && ind0val2 > 0 + sigma;
   bool   ind0short = ind0val1 > 0 + sigma && ind0val2 < 0 - sigma;
   // Moving Average (Simple, Close, 8, 0)
   double ind1val1  = iMA(NULL, 0, 8, 0, MODE_SMA, PRICE_CLOSE, 1);
   double ind1val2  = iMA(NULL, 0, 8, 0, MODE_SMA, PRICE_CLOSE, 2);
   bool   ind1long  = ind1val1 > ind1val2 + sigma;
   bool   ind1short = ind1val1 < ind1val2 - sigma;

   return CreateEntrySignal(37, ind0long && ind1long, ind0short && ind1short, 19, 707, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_037()
  {
   // RSI (Close, 31), Level: 17
   double ind2val1  = iRSI(NULL, 0, 31, PRICE_CLOSE, 1);
   bool   ind2long  = ind2val1 < 17 - sigma;
   bool   ind2short = ind2val1 > 100 - 17 + sigma;
   // Commodity Channel Index (Typical, 31)
   double ind3val1  = iCCI(NULL, 0, 31, PRICE_TYPICAL, 1);
   double ind3val2  = iCCI(NULL, 0, 31, PRICE_TYPICAL, 2);
   bool   ind3long  = ind3val1 > ind3val2 + sigma;
   bool   ind3short = ind3val1 < ind3val2 - sigma;
   // Alligator (Simple, Median, 36, 23, 23, 15, 15, 5)
   double ind4val1  = iAlligator(NULL, 0, 36, 23, 23, 15, 15, 5, MODE_SMA, PRICE_MEDIAN, MODE_GATORJAW,   1);
   double ind4val2  = iAlligator(NULL, 0, 36, 23, 23, 15, 15, 5, MODE_SMA, PRICE_MEDIAN, MODE_GATORJAW,   2);
   bool   ind4long  = ind4val1 < ind4val2 - sigma;
   bool   ind4short = ind4val1 > ind4val2 + sigma;

   return CreateExitSignal(37, ind2long || ind3long || ind4long, ind2short || ind3short || ind4short, 19, 707, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_038()
  {
   // Moving Average (Simple, Close, 47, 25)
   double ind0val1  = iMA(NULL, 0, 47, 25, MODE_SMA, PRICE_CLOSE, 1);
   double ind0val2  = iMA(NULL, 0, 47, 25, MODE_SMA, PRICE_CLOSE, 2);
   bool   ind0long  = Open(0) < ind0val1 - sigma && Open(1) > ind0val2 + sigma;
   bool   ind0short = Open(0) > ind0val1 + sigma && Open(1) < ind0val2 - sigma;

   return CreateEntrySignal(38, ind0long, ind0short, 16, 0, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_038()
  {
   // Moving Averages Crossover (Simple, Simple, 17, 45)
   double ind1val1  = iMA(NULL, 0, 17, 0, MODE_SMA, PRICE_CLOSE, 1);
   double ind1val2  = iMA(NULL, 0, 45, 0, MODE_SMA, PRICE_CLOSE, 1);
   bool   ind1long  = ind1val1 > ind1val2 + sigma;
   bool   ind1short = ind1val1 < ind1val2 - sigma;
   // DeMarker (12)
   double ind2val1  = iDeMarker(NULL, 0, 12, 1);
   double ind2val2  = iDeMarker(NULL, 0, 12, 2);
   double ind2val3  = iDeMarker(NULL, 0, 12, 3);
   bool   ind2long  = ind2val1 > ind2val2 + sigma && ind2val2 < ind2val3 - sigma;
   bool   ind2short = ind2val1 < ind2val2 - sigma && ind2val2 > ind2val3 + sigma;

   return CreateExitSignal(38, ind1long || ind2long, ind1short || ind2short, 16, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_039()
  {
   // MACD Signal (Close, 17, 42, 3)
   double ind0val1  = iMACD(NULL, 0, 17, 42, 3, PRICE_CLOSE, MODE_MAIN, 1) - iMACD(NULL, 0, 17, 42, 3, PRICE_CLOSE ,MODE_SIGNAL, 1);
   double ind0val2  = iMACD(NULL, 0, 17, 42, 3, PRICE_CLOSE, MODE_MAIN, 2) - iMACD(NULL, 0, 17, 42, 3, PRICE_CLOSE ,MODE_SIGNAL, 2);
   bool   ind0long  = ind0val1 < 0 - sigma && ind0val2 > 0 + sigma;
   bool   ind0short = ind0val1 > 0 + sigma && ind0val2 < 0 - sigma;
   // Commodity Channel Index (Typical, 33)
   double ind1val1  = iCCI(NULL, 0, 33, PRICE_TYPICAL, 1);
   double ind1val2  = iCCI(NULL, 0, 33, PRICE_TYPICAL, 2);
   bool   ind1long  = ind1val1 < ind1val2 - sigma;
   bool   ind1short = ind1val1 > ind1val2 + sigma;
   // Williams' Percent Range (8), Level: -54.0
   double ind2val1  = iWPR(NULL, 0, 8, 1);
   bool   ind2long  = ind2val1 < -54.0 - sigma;
   bool   ind2short = ind2val1 > -100 - -54.0 + sigma;

   return CreateEntrySignal(39, ind0long && ind1long && ind2long, ind0short && ind1short && ind2short, 24, 797, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_039()
  {
   // DeMarker (43)
   double ind3val1  = iDeMarker(NULL, 0, 43, 1);
   double ind3val2  = iDeMarker(NULL, 0, 43, 2);
   bool   ind3long  = ind3val1 < ind3val2 - sigma;
   bool   ind3short = ind3val1 > ind3val2 + sigma;
   // DeMarker (24)
   double ind4val1  = iDeMarker(NULL, 0, 24, 1);
   double ind4val2  = iDeMarker(NULL, 0, 24, 2);
   double ind4val3  = iDeMarker(NULL, 0, 24, 3);
   bool   ind4long  = ind4val1 < ind4val2 - sigma && ind4val2 > ind4val3 + sigma;
   bool   ind4short = ind4val1 > ind4val2 + sigma && ind4val2 < ind4val3 - sigma;
   // Momentum (Close, 32), Level: 100.0000
   double ind5val1  = iMomentum(NULL, 0, 32, PRICE_CLOSE, 1);
   bool   ind5long  = ind5val1 > 100.0000 + sigma;
   bool   ind5short = ind5val1 < 200 - 100.0000 - sigma;

   return CreateExitSignal(39, ind3long || ind4long || ind5long, ind3short || ind4short || ind5short, 24, 797, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_040()
  {
   // RSI (Close, 15), Level: 30
   double ind0val1  = iRSI(NULL, 0, 15, PRICE_CLOSE, 1);
   double ind0val2  = iRSI(NULL, 0, 15, PRICE_CLOSE, 2);
   bool   ind0long  = ind0val1 > 30 + sigma && ind0val2 < 30 - sigma;
   bool   ind0short = ind0val1 < 100 - 30 - sigma && ind0val2 > 100 - 30 + sigma;

   return CreateEntrySignal(40, ind0long, ind0short, 12, 670, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_040()
  {
   // Williams' Percent Range (41)
   double ind1val1  = iWPR(NULL, 0, 41, 1);
   double ind1val2  = iWPR(NULL, 0, 41, 2);
   double ind1val3  = iWPR(NULL, 0, 41, 3);
   bool   ind1long  = ind1val1 > ind1val2 + sigma && ind1val2 < ind1val3 - sigma;
   bool   ind1short = ind1val1 < ind1val2 - sigma && ind1val2 > ind1val3 + sigma;
   // Stochastic (4, 1, 3), Level: 66.0
   double ind2val1  = iStochastic(NULL, 0, 4, 1, 3, MODE_SMA, STO_LOWHIGH, MODE_MAIN, 1);
   bool   ind2long  = ind2val1 > 66.0 + sigma;
   bool   ind2short = ind2val1 < 100 - 66.0 - sigma;
   // Stochastic (5, 5, 5)
   double ind3val1  = iStochastic(NULL, 0, 5, 5, 5, MODE_SMA, STO_LOWHIGH, MODE_MAIN, 1);
   double ind3val2  = iStochastic(NULL, 0, 5, 5, 5, MODE_SMA, STO_LOWHIGH, MODE_MAIN, 2);
   bool   ind3long  = ind3val1 > ind3val2 + sigma;
   bool   ind3short = ind3val1 < ind3val2 - sigma;

   return CreateExitSignal(40, ind1long || ind2long || ind3long, ind1short || ind2short || ind3short, 12, 670, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_041()
  {
   // Commodity Channel Index (Typical, 21), Level: 0
   double ind0val1  = iCCI(NULL, 0, 21, PRICE_TYPICAL, 1);
   double ind0val2  = iCCI(NULL, 0, 21, PRICE_TYPICAL, 2);
   bool   ind0long  = ind0val1 < 0 - sigma && ind0val2 > 0 + sigma;
   bool   ind0short = ind0val1 > 0 + sigma && ind0val2 < 0 - sigma;
   // Standard Deviation (Close, Simple, 12)
   double ind1val1  = iStdDev(NULL , 0, 12, 0, MODE_SMA, PRICE_CLOSE, 1);
   double ind1val2  = iStdDev(NULL , 0, 12, 0, MODE_SMA, PRICE_CLOSE, 2);
   bool   ind1long  = ind1val1 < ind1val2 - sigma;
   bool   ind1short = ind1long;

   return CreateEntrySignal(41, ind0long && ind1long, ind0short && ind1short, 14, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_041()
  {
   // Moving Averages Crossover (Simple, Smoothed, 19, 39)
   double ind2val1  = iMA(NULL, 0, 19, 0, MODE_SMA, PRICE_CLOSE, 1);
   double ind2val2  = iMA(NULL, 0, 39, 0, MODE_SMMA, PRICE_CLOSE, 1);
   bool   ind2long  = ind2val1 > ind2val2 + sigma;
   bool   ind2short = ind2val1 < ind2val2 - sigma;

   return CreateExitSignal(41, ind2long, ind2short, 14, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_042()
  {
   // MACD Signal (Close, 21, 45, 6)
   double ind0val1  = iMACD(NULL, 0, 21, 45, 6, PRICE_CLOSE, MODE_MAIN, 1) - iMACD(NULL, 0, 21, 45, 6, PRICE_CLOSE ,MODE_SIGNAL, 1);
   double ind0val2  = iMACD(NULL, 0, 21, 45, 6, PRICE_CLOSE, MODE_MAIN, 2) - iMACD(NULL, 0, 21, 45, 6, PRICE_CLOSE ,MODE_SIGNAL, 2);
   bool   ind0long  = ind0val1 < 0 - sigma && ind0val2 > 0 + sigma;
   bool   ind0short = ind0val1 > 0 + sigma && ind0val2 < 0 - sigma;

   return CreateEntrySignal(42, ind0long, ind0short, 13, 597, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_042()
  {
   // Stochastic (15, 15, 4), Level: 76.0
   double ind1val1  = iStochastic(NULL, 0, 15, 15, 4, MODE_SMA, STO_LOWHIGH, MODE_MAIN, 1);
   bool   ind1long  = ind1val1 > 76.0 + sigma;
   bool   ind1short = ind1val1 < 100 - 76.0 - sigma;
   // Directional Indicators (17)
   double ind2val1  = iADX(NULL, 0, 17, PRICE_CLOSE, 1, 1);
   double ind2val2  = iADX(NULL ,0 ,17, PRICE_CLOSE, 2, 1);
   bool   ind2long  = ind2val1 > ind2val2 + sigma;
   bool   ind2short = ind2val1 < ind2val2 - sigma;

   return CreateExitSignal(42, ind1long || ind2long, ind1short || ind2short, 13, 597, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_043()
  {
   // Stochastic (13, 8, 13), Level: 58.0
   double ind0val1  = iStochastic(NULL, 0, 13, 8, 13, MODE_SMA, STO_LOWHIGH, MODE_MAIN, 1);
   double ind0val2  = iStochastic(NULL, 0, 13, 8, 13, MODE_SMA, STO_LOWHIGH, MODE_MAIN, 2);
   bool   ind0long  = ind0val1 < 58.0 - sigma && ind0val2 > 58.0 + sigma;
   bool   ind0short = ind0val1 > 100 - 58.0 + sigma && ind0val2 < 100 - 58.0 - sigma;

   return CreateEntrySignal(43, ind0long, ind0short, 23, 899, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_043()
  {
   // ADX (13), Level: 39.0
   double ind1val1  = iADX(NULL, 0, 13, PRICE_CLOSE, 0, 1);
   bool   ind1long  = ind1val1 > 39.0 + sigma;
   bool   ind1short = ind1long;
   // ADX (8)
   double ind2val1  = iADX(NULL, 0, 8, PRICE_CLOSE, 0, 1);
   double ind2val2  = iADX(NULL, 0, 8, PRICE_CLOSE, 0, 2);
   double ind2val3  = iADX(NULL, 0, 8, PRICE_CLOSE, 0, 3);
   bool   ind2long  = ind2val1 < ind2val2 - sigma && ind2val2 > ind2val3 + sigma;
   bool   ind2short = ind2long;
   // Williams' Percent Range (23)
   double ind3val1  = iWPR(NULL, 0, 23, 1);
   double ind3val2  = iWPR(NULL, 0, 23, 2);
   double ind3val3  = iWPR(NULL, 0, 23, 3);
   bool   ind3long  = ind3val1 < ind3val2 - sigma && ind3val2 > ind3val3 + sigma;
   bool   ind3short = ind3val1 > ind3val2 + sigma && ind3val2 < ind3val3 - sigma;

   return CreateExitSignal(43, ind1long || ind2long || ind3long, ind1short || ind2short || ind3short, 23, 899, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_044()
  {
   // Directional Indicators (20)
   double ind0val1  = iADX(NULL, 0, 20, PRICE_CLOSE, 1, 1);
   double ind0val2  = iADX(NULL ,0 ,20, PRICE_CLOSE, 2, 1);
   double ind0val3  = iADX(NULL, 0, 20, PRICE_CLOSE, 1, 2);
   double ind0val4  = iADX(NULL ,0 ,20, PRICE_CLOSE, 2, 2);
   bool   ind0long  = ind0val1 < ind0val2 - sigma && ind0val3 > ind0val4 + sigma;
   bool   ind0short = ind0val1 > ind0val2 + sigma && ind0val3 < ind0val4 - sigma;

   return CreateEntrySignal(44, ind0long, ind0short, 15, 504, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_044()
  {
   // Accelerator Oscillator
   double ind1val1  = iAC(NULL, 0, 1);
   double ind1val2  = iAC(NULL, 0, 2);
   bool   ind1long  = ind1val1 < ind1val2 - sigma;
   bool   ind1short = ind1val1 > ind1val2 + sigma;

   return CreateExitSignal(44, ind1long, ind1short, 15, 504, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_045()
  {
   // Bollinger Bands (Close, 39, 1.17)
   double ind0upBand1 = iBands(NULL, 0, 39, 1.17, 0, PRICE_CLOSE, MODE_UPPER, 1);
   double ind0dnBand1 = iBands(NULL, 0, 39, 1.17, 0, PRICE_CLOSE, MODE_LOWER, 1);
   double ind0upBand2 = iBands(NULL, 0, 39, 1.17, 0, PRICE_CLOSE, MODE_UPPER, 2);
   double ind0dnBand2 = iBands(NULL, 0, 39, 1.17, 0, PRICE_CLOSE, MODE_LOWER, 2);
   bool   ind0long    = Open(0) > ind0upBand1 + sigma && Open(1) < ind0upBand2 - sigma;
   bool   ind0short   = Open(0) < ind0dnBand1 - sigma && Open(1) > ind0dnBand2 + sigma;
   // Momentum (Close, 7)
   double ind1val1  = iMomentum(NULL, 0, 7, PRICE_CLOSE, 1);
   double ind1val2  = iMomentum(NULL, 0, 7, PRICE_CLOSE, 2);
   double ind1val3  = iMomentum(NULL, 0, 7, PRICE_CLOSE, 3);
   bool   ind1long  = ind1val1 > ind1val2 + sigma && ind1val2 < ind1val3 - sigma;
   bool   ind1short = ind1val1 < ind1val2 - sigma && ind1val2 > ind1val3 + sigma;

   return CreateEntrySignal(45, ind0long && ind1long, ind0short && ind1short, 21, 0, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_045()
  {
   // Directional Indicators (48)
   double ind2val1  = iADX(NULL, 0, 48, PRICE_CLOSE, 1, 1);
   double ind2val2  = iADX(NULL ,0 ,48, PRICE_CLOSE, 2, 1);
   double ind2val3  = iADX(NULL, 0, 48, PRICE_CLOSE, 1, 2);
   double ind2val4  = iADX(NULL ,0 ,48, PRICE_CLOSE, 2, 2);
   bool   ind2long  = ind2val1 < ind2val2 - sigma && ind2val3 > ind2val4 + sigma;
   bool   ind2short = ind2val1 > ind2val2 + sigma && ind2val3 < ind2val4 - sigma;
   // Stochastic (9, 6, 9)
   double ind3val1  = iStochastic(NULL, 0, 9, 6, 9, MODE_SMA, STO_LOWHIGH, MODE_MAIN, 1);
   double ind3val2  = iStochastic(NULL, 0, 9, 6, 9, MODE_SMA, STO_LOWHIGH, MODE_MAIN, 2);
   bool   ind3long  = ind3val1 > ind3val2 + sigma;
   bool   ind3short = ind3val1 < ind3val2 - sigma;

   return CreateExitSignal(45, ind2long || ind3long, ind2short || ind3short, 21, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_046()
  {
   // Directional Indicators (19)
   double ind0val1  = iADX(NULL, 0, 19, PRICE_CLOSE, 1, 1);
   double ind0val2  = iADX(NULL ,0 ,19, PRICE_CLOSE, 2, 1);
   double ind0val3  = iADX(NULL, 0, 19, PRICE_CLOSE, 1, 2);
   double ind0val4  = iADX(NULL ,0 ,19, PRICE_CLOSE, 2, 2);
   bool   ind0long  = ind0val1 < ind0val2 - sigma && ind0val3 > ind0val4 + sigma;
   bool   ind0short = ind0val1 > ind0val2 + sigma && ind0val3 < ind0val4 - sigma;

   return CreateEntrySignal(46, ind0long, ind0short, 11, 887, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_046()
  {
   // Standard Deviation (Close, Exponential, 45), Level: 0.0014
   double ind1val1  = iStdDev(NULL , 0, 45, 0, MODE_EMA, PRICE_CLOSE, 1);
   double ind1val2  = iStdDev(NULL , 0, 45, 0, MODE_EMA, PRICE_CLOSE, 2);
   bool   ind1long  = ind1val1 < 0.0014 - sigma && ind1val2 > 0.0014 + sigma;
   bool   ind1short = ind1long;
   // Awesome Oscillator
   double ind2val1  = iAO(NULL, 0, 1);
   double ind2val2  = iAO(NULL, 0, 2);
   bool   ind2long  = ind2val1 < ind2val2 - sigma;
   bool   ind2short = ind2val1 > ind2val2 + sigma;

   return CreateExitSignal(46, ind1long || ind2long, ind1short || ind2short, 11, 887, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_047()
  {
   // Awesome Oscillator
   double ind0val1  = iAO(NULL, 0, 1);
   double ind0val2  = iAO(NULL, 0, 2);
   bool   ind0long  = ind0val1 < ind0val2 - sigma;
   bool   ind0short = ind0val1 > ind0val2 + sigma;
   // Envelopes (Close, Simple, 15, 0.07)
   double ind1upBand1 = iEnvelopes(NULL, 0, 15, MODE_SMA, 0, PRICE_CLOSE, 0.07, MODE_UPPER, 1);
   double ind1dnBand1 = iEnvelopes(NULL, 0, 15, MODE_SMA, 0, PRICE_CLOSE, 0.07, MODE_LOWER, 1);
   double ind1upBand2 = iEnvelopes(NULL, 0, 15, MODE_SMA, 0, PRICE_CLOSE, 0.07, MODE_UPPER, 2);
   double ind1dnBand2 = iEnvelopes(NULL, 0, 15, MODE_SMA, 0, PRICE_CLOSE, 0.07, MODE_LOWER, 2);
   bool   ind1long    = Open(0) < ind1upBand1 - sigma && Open(1) > ind1upBand2 + sigma;
   bool   ind1short   = Open(0) > ind1dnBand1 + sigma && Open(1) < ind1dnBand2 - sigma;

   return CreateEntrySignal(47, ind0long && ind1long, ind0short && ind1short, 21, 670, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_047()
  {
   // Alligator (Weighted, Median, 18, 16, 16, 14, 14, 4)
   double ind2val1  = iAlligator(NULL, 0, 18, 16, 16, 14, 14, 4, MODE_LWMA, PRICE_MEDIAN, MODE_GATORTEETH, 1);
   double ind2val2  = iAlligator(NULL, 0, 18, 16, 16, 14, 14, 4, MODE_LWMA, PRICE_MEDIAN, MODE_GATORTEETH, 2);
   bool   ind2long  = ind2val1 > ind2val2 + sigma;
   bool   ind2short = ind2val1 < ind2val2 - sigma;
   // Alligator (Smoothed, Median, 39, 22, 22, 9, 9, 1)
   double ind3val1  = iAlligator(NULL, 0, 39, 22, 22, 9, 9, 1, MODE_SMMA, PRICE_MEDIAN, MODE_GATORLIPS,  1);
   double ind3val2  = iAlligator(NULL, 0, 39, 22, 22, 9, 9, 1, MODE_SMMA, PRICE_MEDIAN, MODE_GATORLIPS,  2);
   bool   ind3long  = ind3val1 < ind3val2 - sigma;
   bool   ind3short = ind3val1 > ind3val2 + sigma;

   return CreateExitSignal(47, ind2long || ind3long, ind2short || ind3short, 21, 670, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_048()
  {
   // MACD Signal (Close, 17, 46, 4)
   double ind0val1  = iMACD(NULL, 0, 17, 46, 4, PRICE_CLOSE, MODE_MAIN, 1) - iMACD(NULL, 0, 17, 46, 4, PRICE_CLOSE ,MODE_SIGNAL, 1);
   double ind0val2  = iMACD(NULL, 0, 17, 46, 4, PRICE_CLOSE, MODE_MAIN, 2) - iMACD(NULL, 0, 17, 46, 4, PRICE_CLOSE ,MODE_SIGNAL, 2);
   bool   ind0long  = ind0val1 < 0 - sigma && ind0val2 > 0 + sigma;
   bool   ind0short = ind0val1 > 0 + sigma && ind0val2 < 0 - sigma;

   return CreateEntrySignal(48, ind0long, ind0short, 15, 0, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_048()
  {
   // Momentum (Close, 13)
   double ind1val1  = iMomentum(NULL, 0, 13, PRICE_CLOSE, 1);
   double ind1val2  = iMomentum(NULL, 0, 13, PRICE_CLOSE, 2);
   bool   ind1long  = ind1val1 < ind1val2 - sigma;
   bool   ind1short = ind1val1 > ind1val2 + sigma;
   // Envelopes (Close, Simple, 25, 0.19)
   double ind2upBand1 = iEnvelopes(NULL, 0, 25, MODE_SMA, 0, PRICE_CLOSE, 0.19, MODE_UPPER, 1);
   double ind2dnBand1 = iEnvelopes(NULL, 0, 25, MODE_SMA, 0, PRICE_CLOSE, 0.19, MODE_LOWER, 1);
   double ind2upBand2 = iEnvelopes(NULL, 0, 25, MODE_SMA, 0, PRICE_CLOSE, 0.19, MODE_UPPER, 2);
   double ind2dnBand2 = iEnvelopes(NULL, 0, 25, MODE_SMA, 0, PRICE_CLOSE, 0.19, MODE_LOWER, 2);
   bool   ind2long    = Open(0) < ind2dnBand1 - sigma && Open(1) > ind2dnBand2 + sigma;
   bool   ind2short   = Open(0) > ind2upBand1 + sigma && Open(1) < ind2upBand2 - sigma;
   // Stochastic Signal (8, 3, 3)
   double ind3val1  = iStochastic(NULL, 0, 8, 3, 3, MODE_SMA, 0, MODE_MAIN,   1);
   double ind3val2  = iStochastic(NULL, 0, 8, 3, 3, MODE_SMA, 0, MODE_SIGNAL, 1);
   double ind3val3  = iStochastic(NULL, 0, 8, 3, 3, MODE_SMA, 0, MODE_MAIN,   2);
   double ind3val4  = iStochastic(NULL, 0, 8, 3, 3, MODE_SMA, 0, MODE_SIGNAL, 2);
   bool   ind3long  = ind3val1 < ind3val2 - sigma && ind3val3 > ind3val4 + sigma;
   bool   ind3short = ind3val1 > ind3val2 + sigma && ind3val3 < ind3val4 - sigma;

   return CreateExitSignal(48, ind1long || ind2long || ind3long, ind1short || ind2short || ind3short, 15, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_049()
  {
   // Stochastic Signal (16, 7, 12)
   double ind0val1  = iStochastic(NULL, 0, 16, 7, 12, MODE_SMA, 0, MODE_MAIN,   1);
   double ind0val2  = iStochastic(NULL, 0, 16, 7, 12, MODE_SMA, 0, MODE_SIGNAL, 1);
   double ind0val3  = iStochastic(NULL, 0, 16, 7, 12, MODE_SMA, 0, MODE_MAIN,   2);
   double ind0val4  = iStochastic(NULL, 0, 16, 7, 12, MODE_SMA, 0, MODE_SIGNAL, 2);
   bool   ind0long  = ind0val1 < ind0val2 - sigma && ind0val3 > ind0val4 + sigma;
   bool   ind0short = ind0val1 > ind0val2 + sigma && ind0val3 < ind0val4 - sigma;
   // Bollinger Bands (Close, 45, 1.20)
   double ind1upBand1 = iBands(NULL, 0, 45, 1.20, 0, PRICE_CLOSE, MODE_UPPER, 1);
   double ind1dnBand1 = iBands(NULL, 0, 45, 1.20, 0, PRICE_CLOSE, MODE_LOWER, 1);
   bool   ind1long  = Open(0) > ind1upBand1 + sigma;
   bool   ind1short = Open(0) < ind1dnBand1 - sigma;

   return CreateEntrySignal(49, ind0long && ind1long, ind0short && ind1short, 18, 122, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_049()
  {
   // DeMarker (27)
   double ind2val1  = iDeMarker(NULL, 0, 27, 1);
   double ind2val2  = iDeMarker(NULL, 0, 27, 2);
   bool   ind2long  = ind2val1 < ind2val2 - sigma;
   bool   ind2short = ind2val1 > ind2val2 + sigma;
   // Awesome Oscillator, Level: 0.0000
   double ind3val1  = iAO(NULL, 0, 1);
   bool   ind3long  = ind3val1 < 0.0000 - sigma;
   bool   ind3short = ind3val1 > 0.0000 + sigma;
   // Directional Indicators (15)
   double ind4val1  = iADX(NULL, 0, 15, PRICE_CLOSE, 1, 1);
   double ind4val2  = iADX(NULL ,0 ,15, PRICE_CLOSE, 2, 1);
   bool   ind4long  = ind4val1 < ind4val2 - sigma;
   bool   ind4short = ind4val1 > ind4val2 + sigma;

   return CreateExitSignal(49, ind2long || ind3long || ind4long, ind2short || ind3short || ind4short, 18, 122, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_050()
  {
   // Stochastic Signal (16, 7, 12)
   double ind0val1  = iStochastic(NULL, 0, 16, 7, 12, MODE_SMA, 0, MODE_MAIN,   1);
   double ind0val2  = iStochastic(NULL, 0, 16, 7, 12, MODE_SMA, 0, MODE_SIGNAL, 1);
   double ind0val3  = iStochastic(NULL, 0, 16, 7, 12, MODE_SMA, 0, MODE_MAIN,   2);
   double ind0val4  = iStochastic(NULL, 0, 16, 7, 12, MODE_SMA, 0, MODE_SIGNAL, 2);
   bool   ind0long  = ind0val1 < ind0val2 - sigma && ind0val3 > ind0val4 + sigma;
   bool   ind0short = ind0val1 > ind0val2 + sigma && ind0val3 < ind0val4 - sigma;
   // Bollinger Bands (Close, 45, 1.20)
   double ind1upBand1 = iBands(NULL, 0, 45, 1.20, 0, PRICE_CLOSE, MODE_UPPER, 1);
   double ind1dnBand1 = iBands(NULL, 0, 45, 1.20, 0, PRICE_CLOSE, MODE_LOWER, 1);
   bool   ind1long  = Open(0) > ind1upBand1 + sigma;
   bool   ind1short = Open(0) < ind1dnBand1 - sigma;

   return CreateEntrySignal(50, ind0long && ind1long, ind0short && ind1short, 18, 122, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_050()
  {
   // Directional Indicators (26)
   double ind2val1  = iADX(NULL, 0, 26, PRICE_CLOSE, 1, 1);
   double ind2val2  = iADX(NULL ,0 ,26, PRICE_CLOSE, 2, 1);
   double ind2val3  = iADX(NULL, 0, 26, PRICE_CLOSE, 1, 2);
   double ind2val4  = iADX(NULL ,0 ,26, PRICE_CLOSE, 2, 2);
   bool   ind2long  = ind2val1 < ind2val2 - sigma && ind2val3 > ind2val4 + sigma;
   bool   ind2short = ind2val1 > ind2val2 + sigma && ind2val3 < ind2val4 - sigma;
   // Alligator (Smoothed, Median, 26, 23, 23, 7, 7, 5)
   double ind3val1  = iAlligator(NULL, 0, 26, 23, 23, 7, 7, 5, MODE_SMMA, PRICE_MEDIAN, MODE_GATORTEETH, 1);
   double ind3val2  = iAlligator(NULL, 0, 26, 23, 23, 7, 7, 5, MODE_SMMA, PRICE_MEDIAN, MODE_GATORTEETH, 2);
   bool   ind3long  = ind3val1 > ind3val2 + sigma;
   bool   ind3short = ind3val1 < ind3val2 - sigma;

   return CreateExitSignal(50, ind2long || ind3long, ind2short || ind3short, 18, 122, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_051()
  {
   // Candle Color (6, 1)
   bool ind0long  = false;
   bool ind0short = false;
   {
      int consecutiveBullish = 0;
      int consecutiveBearish = 0;
      double pipVal = pip * 6;

      for (int b = 1 + 2; b > 0; b--)
        {
         consecutiveBullish = Close(b) - Open(b) >= pipVal ? consecutiveBullish + 1 : 0;
         consecutiveBearish = Open(b) - Close(b) >= pipVal ? consecutiveBearish + 1 : 0;
        }

      ind0long  = consecutiveBearish >= 1;
      ind0short = consecutiveBullish >= 1;
   }

   return CreateEntrySignal(51, ind0long, ind0short, 18, 0, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_051()
  {
   // Stochastic Signal (5, 4, 1)
   double ind1val1  = iStochastic(NULL, 0, 5, 4, 1, MODE_SMA, 0, MODE_MAIN,   1);
   double ind1val2  = iStochastic(NULL, 0, 5, 4, 1, MODE_SMA, 0, MODE_SIGNAL, 1);
   double ind1val3  = iStochastic(NULL, 0, 5, 4, 1, MODE_SMA, 0, MODE_MAIN,   2);
   double ind1val4  = iStochastic(NULL, 0, 5, 4, 1, MODE_SMA, 0, MODE_SIGNAL, 2);
   bool   ind1long  = ind1val1 < ind1val2 - sigma && ind1val3 > ind1val4 + sigma;
   bool   ind1short = ind1val1 > ind1val2 + sigma && ind1val3 < ind1val4 - sigma;

   return CreateExitSignal(51, ind1long, ind1short, 18, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_052()
  {
   // Williams' Percent Range (12), Level: -25.0
   double ind0val1  = iWPR(NULL, 0, 12, 1);
   double ind0val2  = iWPR(NULL, 0, 12, 2);
   bool   ind0long  = ind0val1 < -25.0 - sigma && ind0val2 > -25.0 + sigma;
   bool   ind0short = ind0val1 > -100 - -25.0 + sigma && ind0val2 < -100 - -25.0 - sigma;

   return CreateEntrySignal(52, ind0long, ind0short, 21, 0, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_052()
  {
   // Moving Average (Simple, Close, 29, 19)
   double ind1val1  = iMA(NULL, 0, 29, 19, MODE_SMA, PRICE_CLOSE, 1);
   double ind1val2  = iMA(NULL, 0, 29, 19, MODE_SMA, PRICE_CLOSE, 2);
   double ind1val3  = iMA(NULL, 0, 29, 19, MODE_SMA, PRICE_CLOSE, 3);
   bool   ind1long  = ind1val1 < ind1val2 - sigma && ind1val2 > ind1val3 + sigma;
   bool   ind1short = ind1val1 > ind1val2 + sigma && ind1val2 < ind1val3 - sigma;
   // Moving Average (Simple, Close, 10, 0)
   double ind2val1  = iMA(NULL, 0, 10, 0, MODE_SMA, PRICE_CLOSE, 1);
   bool   ind2long  = Open(0) > ind2val1 + sigma;
   bool   ind2short = Open(0) < ind2val1 - sigma;

   return CreateExitSignal(52, ind1long || ind2long, ind1short || ind2short, 21, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_053()
  {
   // Alligator (Exponential, Median, 35, 23, 23, 7, 7, 2)
   double ind0val1  = iAlligator(NULL, 0, 35, 23, 23, 7, 7, 2, MODE_EMA, PRICE_MEDIAN, MODE_GATORTEETH, 1);
   double ind0val2  = iAlligator(NULL, 0, 35, 23, 23, 7, 7, 2, MODE_EMA, PRICE_MEDIAN, MODE_GATORJAW,   1);
   double ind0val3  = iAlligator(NULL, 0, 35, 23, 23, 7, 7, 2, MODE_EMA, PRICE_MEDIAN, MODE_GATORTEETH, 2);
   double ind0val4  = iAlligator(NULL, 0, 35, 23, 23, 7, 7, 2, MODE_EMA, PRICE_MEDIAN, MODE_GATORJAW,   2);
   bool   ind0long  = ind0val1 > ind0val2 + sigma && ind0val3 < ind0val4 - sigma;
   bool   ind0short = ind0val1 < ind0val2 - sigma && ind0val3 > ind0val4 + sigma;

   return CreateEntrySignal(53, ind0long, ind0short, 13, 54, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_053()
  {
   // Standard Deviation (Close, Simple, 6)
   double ind1val1  = iStdDev(NULL , 0, 6, 0, MODE_SMA, PRICE_CLOSE, 1);
   double ind1val2  = iStdDev(NULL , 0, 6, 0, MODE_SMA, PRICE_CLOSE, 2);
   bool   ind1long  = ind1val1 > ind1val2 + sigma;
   bool   ind1short = ind1long;

   return CreateExitSignal(53, ind1long, ind1short, 13, 54, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_054()
  {
   // MACD Signal (Close, 17, 46, 4)
   double ind0val1  = iMACD(NULL, 0, 17, 46, 4, PRICE_CLOSE, MODE_MAIN, 1) - iMACD(NULL, 0, 17, 46, 4, PRICE_CLOSE ,MODE_SIGNAL, 1);
   double ind0val2  = iMACD(NULL, 0, 17, 46, 4, PRICE_CLOSE, MODE_MAIN, 2) - iMACD(NULL, 0, 17, 46, 4, PRICE_CLOSE ,MODE_SIGNAL, 2);
   bool   ind0long  = ind0val1 < 0 - sigma && ind0val2 > 0 + sigma;
   bool   ind0short = ind0val1 > 0 + sigma && ind0val2 < 0 - sigma;

   return CreateEntrySignal(54, ind0long, ind0short, 15, 0, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_054()
  {
   // Directional Indicators (45)
   double ind1val1  = iADX(NULL, 0, 45, PRICE_CLOSE, 1, 1);
   double ind1val2  = iADX(NULL ,0 ,45, PRICE_CLOSE, 2, 1);
   bool   ind1long  = ind1val1 < ind1val2 - sigma;
   bool   ind1short = ind1val1 > ind1val2 + sigma;
   // Envelopes (Close, Simple, 25, 0.19)
   double ind2upBand1 = iEnvelopes(NULL, 0, 25, MODE_SMA, 0, PRICE_CLOSE, 0.19, MODE_UPPER, 1);
   double ind2dnBand1 = iEnvelopes(NULL, 0, 25, MODE_SMA, 0, PRICE_CLOSE, 0.19, MODE_LOWER, 1);
   double ind2upBand2 = iEnvelopes(NULL, 0, 25, MODE_SMA, 0, PRICE_CLOSE, 0.19, MODE_UPPER, 2);
   double ind2dnBand2 = iEnvelopes(NULL, 0, 25, MODE_SMA, 0, PRICE_CLOSE, 0.19, MODE_LOWER, 2);
   bool   ind2long    = Open(0) < ind2dnBand1 - sigma && Open(1) > ind2dnBand2 + sigma;
   bool   ind2short   = Open(0) > ind2upBand1 + sigma && Open(1) < ind2upBand2 - sigma;
   // Stochastic Signal (8, 3, 3)
   double ind3val1  = iStochastic(NULL, 0, 8, 3, 3, MODE_SMA, 0, MODE_MAIN,   1);
   double ind3val2  = iStochastic(NULL, 0, 8, 3, 3, MODE_SMA, 0, MODE_SIGNAL, 1);
   double ind3val3  = iStochastic(NULL, 0, 8, 3, 3, MODE_SMA, 0, MODE_MAIN,   2);
   double ind3val4  = iStochastic(NULL, 0, 8, 3, 3, MODE_SMA, 0, MODE_SIGNAL, 2);
   bool   ind3long  = ind3val1 < ind3val2 - sigma && ind3val3 > ind3val4 + sigma;
   bool   ind3short = ind3val1 > ind3val2 + sigma && ind3val3 < ind3val4 - sigma;

   return CreateExitSignal(54, ind1long || ind2long || ind3long, ind1short || ind2short || ind3short, 15, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_055()
  {
   // Alligator (Exponential, Median, 33, 23, 23, 10, 10, 4)
   double ind0val1  = iAlligator(NULL, 0, 33, 23, 23, 10, 10, 4, MODE_EMA, PRICE_MEDIAN, MODE_GATORLIPS,  1);
   double ind0val2  = iAlligator(NULL, 0, 33, 23, 23, 10, 10, 4, MODE_EMA, PRICE_MEDIAN, MODE_GATORTEETH, 1);
   double ind0val3  = iAlligator(NULL, 0, 33, 23, 23, 10, 10, 4, MODE_EMA, PRICE_MEDIAN, MODE_GATORLIPS,  2);
   double ind0val4  = iAlligator(NULL, 0, 33, 23, 23, 10, 10, 4, MODE_EMA, PRICE_MEDIAN, MODE_GATORTEETH, 2);
   bool   ind0long  = ind0val1 < ind0val2 - sigma && ind0val3 > ind0val4 + sigma;
   bool   ind0short = ind0val1 > ind0val2 + sigma && ind0val3 < ind0val4 - sigma;

   return CreateEntrySignal(55, ind0long, ind0short, 21, 0, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_055()
  {
   // Directional Indicators (42)
   double ind1val1  = iADX(NULL, 0, 42, PRICE_CLOSE, 1, 1);
   double ind1val2  = iADX(NULL ,0 ,42, PRICE_CLOSE, 2, 1);
   double ind1val3  = iADX(NULL, 0, 42, PRICE_CLOSE, 1, 2);
   double ind1val4  = iADX(NULL ,0 ,42, PRICE_CLOSE, 2, 2);
   bool   ind1long  = ind1val1 > ind1val2 + sigma && ind1val3 < ind1val4 - sigma;
   bool   ind1short = ind1val1 < ind1val2 - sigma && ind1val3 > ind1val4 + sigma;
   // Stochastic Signal (10, 6, 7)
   double ind2val1  = iStochastic(NULL, 0, 10, 6, 7, MODE_SMA, 0, MODE_MAIN,   1);
   double ind2val2  = iStochastic(NULL, 0, 10, 6, 7, MODE_SMA, 0, MODE_SIGNAL, 1);
   double ind2val3  = iStochastic(NULL, 0, 10, 6, 7, MODE_SMA, 0, MODE_MAIN,   2);
   double ind2val4  = iStochastic(NULL, 0, 10, 6, 7, MODE_SMA, 0, MODE_SIGNAL, 2);
   bool   ind2long  = ind2val1 > ind2val2 + sigma && ind2val3 < ind2val4 - sigma;
   bool   ind2short = ind2val1 < ind2val2 - sigma && ind2val3 > ind2val4 + sigma;

   return CreateExitSignal(55, ind1long || ind2long, ind1short || ind2short, 21, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_056()
  {
   // Moving Averages Crossover (Simple, Simple, 6, 35)
   double ind0val1  = iMA(NULL, 0, 6, 0, MODE_SMA, PRICE_CLOSE, 1);
   double ind0val2  = iMA(NULL, 0, 35, 0, MODE_SMA, PRICE_CLOSE, 1);
   double ind0val3  = iMA(NULL, 0, 6, 0, MODE_SMA, PRICE_CLOSE, 2);
   double ind0val4  = iMA(NULL, 0, 35, 0, MODE_SMA, PRICE_CLOSE, 2);
   bool   ind0long  = ind0val1 > ind0val2 + sigma && ind0val3 < ind0val4 - sigma;
   bool   ind0short = ind0val1 < ind0val2 - sigma && ind0val3 > ind0val4 + sigma;

   return CreateEntrySignal(56, ind0long, ind0short, 24, 0, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_056()
  {
   // Bollinger Bands (Close, 13, 1.06)
   double ind1upBand1 = iBands(NULL, 0, 13, 1.06, 0, PRICE_CLOSE, MODE_UPPER, 1);
   double ind1dnBand1 = iBands(NULL, 0, 13, 1.06, 0, PRICE_CLOSE, MODE_LOWER, 1);
   bool   ind1long  = Open(0) > ind1upBand1 + sigma;
   bool   ind1short = Open(0) < ind1dnBand1 - sigma;

   return CreateExitSignal(56, ind1long, ind1short, 24, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_057()
  {
   // Stochastic Signal (16, 7, 12)
   double ind0val1  = iStochastic(NULL, 0, 16, 7, 12, MODE_SMA, 0, MODE_MAIN,   1);
   double ind0val2  = iStochastic(NULL, 0, 16, 7, 12, MODE_SMA, 0, MODE_SIGNAL, 1);
   double ind0val3  = iStochastic(NULL, 0, 16, 7, 12, MODE_SMA, 0, MODE_MAIN,   2);
   double ind0val4  = iStochastic(NULL, 0, 16, 7, 12, MODE_SMA, 0, MODE_SIGNAL, 2);
   bool   ind0long  = ind0val1 < ind0val2 - sigma && ind0val3 > ind0val4 + sigma;
   bool   ind0short = ind0val1 > ind0val2 + sigma && ind0val3 < ind0val4 - sigma;
   // Bollinger Bands (Close, 45, 1.20)
   double ind1upBand1 = iBands(NULL, 0, 45, 1.20, 0, PRICE_CLOSE, MODE_UPPER, 1);
   double ind1dnBand1 = iBands(NULL, 0, 45, 1.20, 0, PRICE_CLOSE, MODE_LOWER, 1);
   bool   ind1long  = Open(0) > ind1upBand1 + sigma;
   bool   ind1short = Open(0) < ind1dnBand1 - sigma;

   return CreateEntrySignal(57, ind0long && ind1long, ind0short && ind1short, 18, 122, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_057()
  {
   // RSI (Close, 46)
   double ind2val1  = iRSI(NULL, 0, 46, PRICE_CLOSE, 1);
   double ind2val2  = iRSI(NULL, 0, 46, PRICE_CLOSE, 2);
   bool   ind2long  = ind2val1 > ind2val2 + sigma;
   bool   ind2short = ind2val1 < ind2val2 - sigma;
   // Awesome Oscillator, Level: 0.0000
   double ind3val1  = iAO(NULL, 0, 1);
   bool   ind3long  = ind3val1 < 0.0000 - sigma;
   bool   ind3short = ind3val1 > 0.0000 + sigma;
   // Directional Indicators (15)
   double ind4val1  = iADX(NULL, 0, 15, PRICE_CLOSE, 1, 1);
   double ind4val2  = iADX(NULL ,0 ,15, PRICE_CLOSE, 2, 1);
   bool   ind4long  = ind4val1 < ind4val2 - sigma;
   bool   ind4short = ind4val1 > ind4val2 + sigma;

   return CreateExitSignal(57, ind2long || ind3long || ind4long, ind2short || ind3short || ind4short, 18, 122, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_058()
  {
   // Accelerator Oscillator, Level: 0.0000
   double ind0val1  = iAC(NULL, 0, 1);
   double ind0val2  = iAC(NULL, 0, 2);
   bool   ind0long  = ind0val1 > 0.0000 + sigma && ind0val2 < 0.0000 - sigma;
   bool   ind0short = ind0val1 < 0.0000 - sigma && ind0val2 > 0.0000 + sigma;
   // Directional Indicators (13)
   double ind1val1  = iADX(NULL, 0, 13, PRICE_CLOSE, 1, 1);
   double ind1val2  = iADX(NULL ,0 ,13, PRICE_CLOSE, 2, 1);
   bool   ind1long  = ind1val1 < ind1val2 - sigma;
   bool   ind1short = ind1val1 > ind1val2 + sigma;
   // Average True Range (26), Level: 0.0002
   double ind2val1  = iATR(NULL, 0, 26, 1);
   bool   ind2long  = ind2val1 > 0.0002 + sigma;
   bool   ind2short = ind2long;

   return CreateEntrySignal(58, ind0long && ind1long && ind2long, ind0short && ind1short && ind2short, 21, 0, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_058()
  {
   // Standard Deviation (Close, Simple, 24)
   double ind3val1  = iStdDev(NULL , 0, 24, 0, MODE_SMA, PRICE_CLOSE, 1);
   double ind3val2  = iStdDev(NULL , 0, 24, 0, MODE_SMA, PRICE_CLOSE, 2);
   bool   ind3long  = ind3val1 > ind3val2 + sigma;
   bool   ind3short = ind3long;

   return CreateExitSignal(58, ind3long, ind3short, 21, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_059()
  {
   // Commodity Channel Index (Typical, 19), Level: 0
   double ind0val1  = iCCI(NULL, 0, 19, PRICE_TYPICAL, 1);
   double ind0val2  = iCCI(NULL, 0, 19, PRICE_TYPICAL, 2);
   bool   ind0long  = ind0val1 < 0 - sigma && ind0val2 > 0 + sigma;
   bool   ind0short = ind0val1 > 0 + sigma && ind0val2 < 0 - sigma;
   // Momentum (Close, 46)
   double ind1val1  = iMomentum(NULL, 0, 46, PRICE_CLOSE, 1);
   double ind1val2  = iMomentum(NULL, 0, 46, PRICE_CLOSE, 2);
   double ind1val3  = iMomentum(NULL, 0, 46, PRICE_CLOSE, 3);
   bool   ind1long  = ind1val1 < ind1val2 - sigma && ind1val2 > ind1val3 + sigma;
   bool   ind1short = ind1val1 > ind1val2 + sigma && ind1val2 < ind1val3 - sigma;

   return CreateEntrySignal(59, ind0long && ind1long, ind0short && ind1short, 14, 0, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_059()
  {
   // Williams' Percent Range (17)
   double ind2val1  = iWPR(NULL, 0, 17, 1);
   double ind2val2  = iWPR(NULL, 0, 17, 2);
   bool   ind2long  = ind2val1 > ind2val2 + sigma;
   bool   ind2short = ind2val1 < ind2val2 - sigma;

   return CreateExitSignal(59, ind2long, ind2short, 14, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_060()
  {
   // Stochastic (10, 2, 9)
   double ind0val1  = iStochastic(NULL, 0, 10, 2, 9, MODE_SMA, STO_LOWHIGH, MODE_MAIN, 1);
   double ind0val2  = iStochastic(NULL, 0, 10, 2, 9, MODE_SMA, STO_LOWHIGH, MODE_MAIN, 2);
   double ind0val3  = iStochastic(NULL, 0, 10, 2, 9, MODE_SMA, STO_LOWHIGH, MODE_MAIN, 3);
   bool   ind0long  = ind0val1 > ind0val2 + sigma && ind0val2 < ind0val3 - sigma;
   bool   ind0short = ind0val1 < ind0val2 - sigma && ind0val2 > ind0val3 + sigma;
   // Standard Deviation (Close, Simple, 34)
   double ind1val1  = iStdDev(NULL , 0, 34, 0, MODE_SMA, PRICE_CLOSE, 1);
   double ind1val2  = iStdDev(NULL , 0, 34, 0, MODE_SMA, PRICE_CLOSE, 2);
   bool   ind1long  = ind1val1 > ind1val2 + sigma;
   bool   ind1short = ind1long;

   return CreateEntrySignal(60, ind0long && ind1long, ind0short && ind1short, 17, 431, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_060()
  {
   // Awesome Oscillator
   double ind2val1  = iAO(NULL, 0, 1);
   double ind2val2  = iAO(NULL, 0, 2);
   bool   ind2long  = ind2val1 < ind2val2 - sigma;
   bool   ind2short = ind2val1 > ind2val2 + sigma;
   // Momentum (Close, 20), Level: 99.0000
   double ind3val1  = iMomentum(NULL, 0, 20, PRICE_CLOSE, 1);
   double ind3val2  = iMomentum(NULL, 0, 20, PRICE_CLOSE, 2);
   bool   ind3long  = ind3val1 < 99.0000 - sigma && ind3val2 > 99.0000 + sigma;
   bool   ind3short = ind3val1 > 200 - 99.0000 + sigma && ind3val2 < 200 - 99.0000 - sigma;
   // Average True Range (44)
   double ind4val1  = iATR(NULL, 0, 44, 1);
   double ind4val2  = iATR(NULL, 0, 44, 2);
   bool   ind4long  = ind4val1 > ind4val2 + sigma;
   bool   ind4short = ind4long;

   return CreateExitSignal(60, ind2long || ind3long || ind4long, ind2short || ind3short || ind4short, 17, 431, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_061()
  {
   // Moving Averages Crossover (Simple, Weighted, 11, 25)
   double ind0val1  = iMA(NULL, 0, 11, 0, MODE_SMA, PRICE_CLOSE, 1);
   double ind0val2  = iMA(NULL, 0, 25, 0, MODE_LWMA, PRICE_CLOSE, 1);
   double ind0val3  = iMA(NULL, 0, 11, 0, MODE_SMA, PRICE_CLOSE, 2);
   double ind0val4  = iMA(NULL, 0, 25, 0, MODE_LWMA, PRICE_CLOSE, 2);
   bool   ind0long  = ind0val1 > ind0val2 + sigma && ind0val3 < ind0val4 - sigma;
   bool   ind0short = ind0val1 < ind0val2 - sigma && ind0val3 > ind0val4 + sigma;
   // Momentum (Close, 28)
   double ind1val1  = iMomentum(NULL, 0, 28, PRICE_CLOSE, 1);
   double ind1val2  = iMomentum(NULL, 0, 28, PRICE_CLOSE, 2);
   bool   ind1long  = ind1val1 > ind1val2 + sigma;
   bool   ind1short = ind1val1 < ind1val2 - sigma;

   return CreateEntrySignal(61, ind0long && ind1long, ind0short && ind1short, 22, 0, true, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_061()
  {
   // Bollinger Bands (Close, 8, 3.15)
   double ind2upBand1 = iBands(NULL, 0, 8, 3.15, 0, PRICE_CLOSE, MODE_UPPER, 1);
   double ind2dnBand1 = iBands(NULL, 0, 8, 3.15, 0, PRICE_CLOSE, MODE_LOWER, 1);
   double ind2upBand2 = iBands(NULL, 0, 8, 3.15, 0, PRICE_CLOSE, MODE_UPPER, 2);
   double ind2dnBand2 = iBands(NULL, 0, 8, 3.15, 0, PRICE_CLOSE, MODE_LOWER, 2);
   bool   ind2long    = Open(0) < ind2dnBand1 - sigma && Open(1) > ind2dnBand2 + sigma;
   bool   ind2short   = Open(0) > ind2upBand1 + sigma && Open(1) < ind2upBand2 - sigma;
   // Accelerator Oscillator
   double ind3val1  = iAC(NULL, 0, 1);
   double ind3val2  = iAC(NULL, 0, 2);
   double ind3val3  = iAC(NULL, 0, 3);
   bool   ind3long  = ind3val1 > ind3val2 + sigma && ind3val2 < ind3val3 - sigma;
   bool   ind3short = ind3val1 < ind3val2 - sigma && ind3val2 > ind3val3 + sigma;

   return CreateExitSignal(61, ind2long || ind3long, ind2short || ind3short, 22, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_062()
  {
   // Alligator (Exponential, Median, 47, 25, 25, 9, 9, 4)
   double ind0val1  = iAlligator(NULL, 0, 47, 25, 25, 9, 9, 4, MODE_EMA, PRICE_MEDIAN, MODE_GATORLIPS,  1);
   double ind0val2  = iAlligator(NULL, 0, 47, 25, 25, 9, 9, 4, MODE_EMA, PRICE_MEDIAN, MODE_GATORTEETH, 1);
   double ind0val3  = iAlligator(NULL, 0, 47, 25, 25, 9, 9, 4, MODE_EMA, PRICE_MEDIAN, MODE_GATORLIPS,  2);
   double ind0val4  = iAlligator(NULL, 0, 47, 25, 25, 9, 9, 4, MODE_EMA, PRICE_MEDIAN, MODE_GATORTEETH, 2);
   bool   ind0long  = ind0val1 < ind0val2 - sigma && ind0val3 > ind0val4 + sigma;
   bool   ind0short = ind0val1 > ind0val2 + sigma && ind0val3 < ind0val4 - sigma;

   return CreateEntrySignal(62, ind0long, ind0short, 12, 192, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_062()
  {
   // Stochastic (15, 3, 9)
   double ind1val1  = iStochastic(NULL, 0, 15, 3, 9, MODE_SMA, STO_LOWHIGH, MODE_MAIN, 1);
   double ind1val2  = iStochastic(NULL, 0, 15, 3, 9, MODE_SMA, STO_LOWHIGH, MODE_MAIN, 2);
   double ind1val3  = iStochastic(NULL, 0, 15, 3, 9, MODE_SMA, STO_LOWHIGH, MODE_MAIN, 3);
   bool   ind1long  = ind1val1 > ind1val2 + sigma && ind1val2 < ind1val3 - sigma;
   bool   ind1short = ind1val1 < ind1val2 - sigma && ind1val2 > ind1val3 + sigma;

   return CreateExitSignal(62, ind1long, ind1short, 12, 192, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
ENUM_INIT_RETCODE ValidateInit()
  {
   return INIT_SUCCEEDED;
  }
//+------------------------------------------------------------------+
/*STRATEGY MARKET ICMarketsSC-Demo04; EURUSD; M30 */
