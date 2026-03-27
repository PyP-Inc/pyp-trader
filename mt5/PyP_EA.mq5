//+------------------------------------------------------------------+
//|                                                       PyP EA.mq5 |
//|                                          PyP Trading Platform    |
//|                                    https://pyp.stanlink.online   |
//+------------------------------------------------------------------+
#property copyright "PyP Trading Platform"
#property link      "https://pyp.stanlink.online"
#property version   "3.10"

#include <Trade\Trade.mqh>
CTrade trade;

//--- Inputs
input string EAToken           = "";       // EA Token (from PyP dashboard)
input string DeploymentId      = "";       // Optional deployment_id for exact routing
input string ApiUrl            = "https://api.pyp.stanlink.online"; // API URL
input bool   EnableTrading     = true;     // Enable Auto Trading

//--- Risk Management (0 = use server-calculated value)
input double ManualLotSize     = 0;        // Lot Size (0 = server calculates)
input double ManualSL_Pips     = 0;        // Stop Loss in pips (0 = server calculates)
input double ManualTP_Pips     = 0;        // Take Profit in pips (0 = server calculates)
input double MinConfidence     = 0.0;      // Min confidence to trade (0.0 = accept all)

//--- Order Settings
input ulong  MagicNumber       = 20260101; // Magic Number
input int    Slippage          = 3;        // Slippage (points)
input bool   CloseOnReverse    = true;     // Close opposite on reverse signal

//--- Internal state
datetime lastSignalTime = 0;

//+------------------------------------------------------------------+
int OnInit() {
   if (EAToken == "") {
      Alert("PyP EA: EAToken is required. Get it from your PyP dashboard → Deployments → Generate EA Token.");
      return INIT_FAILED;
   }
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   EventSetTimer(5);
   Print("PyP EA v3.1 initialized. Token: ", StringSubstr(EAToken, 0, 8), "...");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   EventKillTimer();
}

void OnTimer() {
   if (EnableTrading) FetchAndExecuteSignal();
}

//+------------------------------------------------------------------+
void FetchAndExecuteSignal() {
   string url     = BuildSignalUrl();
   string headers = "Content-Type: application/json\r\n";
   char post[], result[];
   string resultHeaders;

   int res = WebRequest("GET", url, headers, 5000, post, result, resultHeaders);

   if (res == -1) {
      if (GetLastError() == 4060)
         Print("PyP EA: Add ", ApiUrl, " to allowed URLs → Tools > Options > Expert Advisors > Allow WebRequests");
      return;
   }
   if (res == 409) {
      Print("PyP EA: ambiguous deployment. Set DeploymentId or use a deployment-specific EA token. Body=", CharArrayToString(result));
      return;
   }
   if (res != 200) {
      Print("PyP EA: API returned HTTP ", res, " Body=", CharArrayToString(result));
      return;
   }

   string body = CharArrayToString(result);
   if (StringFind(body, "signal") < 0) return;

   //--- Parse all fields
   string signal     = ParseJsonString(body, "signal");
   string pair       = ParseJsonString(body, "pair");
   string symbol     = ParseJsonString(body, "symbol");
   string deploymentId = ParseJsonString(body, "deployment_id");
   double confidence = ParseJsonDouble(body, "confidence");
   double sl_price   = ParseJsonDouble(body, "sl");
   double tp_price   = ParseJsonDouble(body, "tp");
   double lot_size   = ParseJsonDouble(body, "lot_size");
   double risk_pct   = ParseJsonDouble(body, "risk_percent");
   double sl_pct     = ParseJsonDouble(body, "stop_loss_percent");
   double tp_pct     = ParseJsonDouble(body, "take_profit_percent");
   double server_slippage = ParseJsonDouble(body, "slippage_pips");
   long   ts         = (long)ParseJsonDouble(body, "timestamp");

   //--- Deduplicate
   if (signal == "" || ts <= (long)lastSignalTime) return;
   lastSignalTime = (datetime)ts;

   //--- Normalize pair
   if (symbol != "") pair = symbol;
   StringReplace(pair, "/", "");
   StringReplace(pair, "_", "");
   if (pair == "") pair = Symbol();

   //--- Confidence gate
   if (MinConfidence > 0.0 && confidence < MinConfidence) {
      Print("PyP EA: Signal skipped — confidence ", DoubleToString(confidence, 2),
            " below threshold ", DoubleToString(MinConfidence, 2));
      return;
   }

   Print("PyP EA: Deployment=", (deploymentId == "" ? "(unresolved)" : deploymentId),
         " Signal=", signal,
         " Pair=", pair,
         " Conf=", DoubleToString(confidence, 2),
         " SL=", DoubleToString(sl_price, 5),
         " TP=", DoubleToString(tp_price, 5),
         " Lots=", DoubleToString(lot_size, 2));

   if (signal == "BUY")  ExecuteTrade(pair, ORDER_TYPE_BUY,  sl_price, tp_price, lot_size, risk_pct, sl_pct, tp_pct, server_slippage);
   if (signal == "SELL") ExecuteTrade(pair, ORDER_TYPE_SELL, sl_price, tp_price, lot_size, risk_pct, sl_pct, tp_pct, server_slippage);
}

string BuildSignalUrl() {
   string pair = Symbol();
   StringReplace(pair, "/", "");
   StringReplace(pair, "_", "");
   StringReplace(pair, " ", "");

   string url = ApiUrl + "/api/mt4/signals?token=" + EAToken + "&since=" + IntegerToString((long)lastSignalTime);
   if (DeploymentId != "") url += "&deployment_id=" + DeploymentId;
   if (pair != "") url += "&pair=" + pair;
   url += "&timeframe=" + NormalizeTimeframe(_Period);
   return url;
}

string NormalizeTimeframe(ENUM_TIMEFRAMES tf) {
   switch (tf) {
      case PERIOD_M1: return "1m";
      case PERIOD_M2: return "2m";
      case PERIOD_M3: return "3m";
      case PERIOD_M4: return "4m";
      case PERIOD_M5: return "5m";
      case PERIOD_M6: return "6m";
      case PERIOD_M10: return "10m";
      case PERIOD_M12: return "12m";
      case PERIOD_M15: return "15m";
      case PERIOD_M20: return "20m";
      case PERIOD_M30: return "30m";
      case PERIOD_H1: return "1h";
      case PERIOD_H2: return "2h";
      case PERIOD_H3: return "3h";
      case PERIOD_H4: return "4h";
      case PERIOD_H6: return "6h";
      case PERIOD_H8: return "8h";
      case PERIOD_H12: return "12h";
      case PERIOD_D1: return "1d";
      case PERIOD_W1: return "1w";
      case PERIOD_MN1: return "1mo";
   }
   return "1h";
}

//+------------------------------------------------------------------+
void ExecuteTrade(string pair, ENUM_ORDER_TYPE orderType,
                  double server_sl, double server_tp, double server_lots,
                  double risk_pct, double sl_pct, double tp_pct, double server_slippage_pips) {

   if (CloseOnReverse) CloseOpposite(pair, orderType);

   SymbolSelect(pair, true);
   double price = (orderType == ORDER_TYPE_BUY)
                  ? SymbolInfoDouble(pair, SYMBOL_ASK)
                  : SymbolInfoDouble(pair, SYMBOL_BID);
   if (price <= 0) return;

   int    digits   = (int)SymbolInfoInteger(pair, SYMBOL_DIGITS);
   double point    = SymbolInfoDouble(pair, SYMBOL_POINT);
   double pipValue = (digits == 3 || digits == 5) ? point * 10 : point;
   double tickValue = SymbolInfoDouble(pair, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(pair, SYMBOL_TRADE_TICK_SIZE);
   double volumeMin = SymbolInfoDouble(pair, SYMBOL_VOLUME_MIN);
   double volumeMax = SymbolInfoDouble(pair, SYMBOL_VOLUME_MAX);
   double volumeStep = SymbolInfoDouble(pair, SYMBOL_VOLUME_STEP);

   int deviationPoints = Slippage;
   if (server_slippage_pips > 0) {
      deviationPoints = (int)MathMax(1, MathRound((server_slippage_pips * pipValue) / point));
   }
   trade.SetDeviationInPoints(deviationPoints);

   //--- Resolve SL
   double sl = 0;
   if (ManualSL_Pips > 0) {
      sl = (orderType == ORDER_TYPE_BUY)
           ? price - ManualSL_Pips * pipValue
           : price + ManualSL_Pips * pipValue;
   } else if (server_sl > 0) {
      sl = server_sl;
   } else if (sl_pct > 0) {
      double slDistance = price * (sl_pct / 100.0);
      sl = (orderType == ORDER_TYPE_BUY)
           ? price - slDistance
           : price + slDistance;
   }

   //--- Resolve lot size
   double lots = (ManualLotSize > 0) ? ManualLotSize : 0;
   if (lots <= 0 && server_lots > 0) lots = server_lots;
   if (lots <= 0 && risk_pct > 0 && sl > 0 && tickValue > 0 && tickSize > 0) {
      double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (risk_pct / 100.0);
      double stopDistance = MathAbs(price - sl);
      double lossPerLot = (stopDistance / tickSize) * tickValue;
      if (lossPerLot > 0) lots = riskAmount / lossPerLot;
   }
   if (lots <= 0) lots = 0.01;
   if (volumeStep > 0) lots = MathFloor(lots / volumeStep) * volumeStep;
   if (volumeMin > 0 && lots < volumeMin) lots = volumeMin;
   if (volumeMax > 0 && lots > volumeMax) lots = volumeMax;

   //--- Resolve TP
   double tp = 0;
   if (ManualTP_Pips > 0) {
      tp = (orderType == ORDER_TYPE_BUY)
           ? price + ManualTP_Pips * pipValue
           : price - ManualTP_Pips * pipValue;
   } else if (server_tp > 0) {
      tp = server_tp;
   } else if (tp_pct > 0) {
      double tpDistance = price * (tp_pct / 100.0);
      tp = (orderType == ORDER_TYPE_BUY)
           ? price + tpDistance
           : price - tpDistance;
   }

   //--- Normalize
   if (sl > 0) sl = NormalizeDouble(sl, digits);
   if (tp > 0) tp = NormalizeDouble(tp, digits);
   lots = NormalizeDouble(lots, 2);

   bool sent = (orderType == ORDER_TYPE_BUY)
               ? trade.Buy(lots, pair, 0.0, sl, tp, "PyP Signal")
               : trade.Sell(lots, pair, 0.0, sl, tp, "PyP Signal");

   if (!sent)
      Print("PyP EA: OrderSend failed, retcode=", trade.ResultRetcode());
   else
      Print("PyP EA: Order opened ticket=", trade.ResultOrder(),
            " type=", (orderType == ORDER_TYPE_BUY ? "BUY" : "SELL"),
            " price=", DoubleToString(price, digits),
            " SL=", DoubleToString(sl, digits),
            " TP=", DoubleToString(tp, digits),
            " lots=", DoubleToString(lots, 2));
}

//+------------------------------------------------------------------+
void CloseOpposite(string pair, ENUM_ORDER_TYPE newType) {
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket)) continue;
      if (PositionGetString(POSITION_SYMBOL) != pair) continue;
      if ((long)PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber) continue;

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if ((newType == ORDER_TYPE_BUY  && posType == POSITION_TYPE_SELL) ||
          (newType == ORDER_TYPE_SELL && posType == POSITION_TYPE_BUY)) {
         trade.PositionClose(ticket);
      }
   }
}

//+------------------------------------------------------------------+
string ParseJsonString(string json, string key) {
   string search = "\"" + key + "\":\"";
   int start = StringFind(json, search);
   if (start < 0) return "";
   start += StringLen(search);
   int end = StringFind(json, "\"", start);
   if (end < 0) return "";
   return StringSubstr(json, start, end - start);
}

double ParseJsonDouble(string json, string key) {
   string search = "\"" + key + "\":";
   int start = StringFind(json, search);
   if (start < 0) return 0;
   start += StringLen(search);
   if (StringGetCharacter(json, start) == '"') start++;
   int end = start;
   while (end < StringLen(json)) {
      ushort c = StringGetCharacter(json, end);
      if (c == ',' || c == '}' || c == '"' || c == ']') break;
      end++;
   }
   return StringToDouble(StringSubstr(json, start, end - start));
}
//+------------------------------------------------------------------+
