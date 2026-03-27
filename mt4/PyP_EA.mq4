//+------------------------------------------------------------------+
//|                                                       PyP EA.mq4 |
//|                                          PyP Trading Platform    |
//|                                    https://pyp.stanlink.online   |
//+------------------------------------------------------------------+
#property copyright "PyP Trading Platform"
#property link      "https://pyp.stanlink.online"
#property version   "3.10"
#property strict

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
input int    MagicNumber       = 20260101; // Magic Number
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
   EventSetTimer(5);
   Print("PyP EA v3.1 initialized. Token: ", StringSubstr(EAToken, 0, 8), "...");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   EventKillTimer();
}

void OnTimer() {
   if (!EnableTrading) return;
   FetchAndExecuteSignal();
}

//+------------------------------------------------------------------+
void FetchAndExecuteSignal() {
   string url     = BuildSignalUrl();
   string headers = "Content-Type: application/json\r\n";
   char post[], result[];
   string resultHeaders;

   int res = WebRequest("GET", url, headers, 5000, post, result, resultHeaders);

   if (res == -1) {
      int err = GetLastError();
      if (err == 4060)
         Print("PyP EA: Add ", ApiUrl, " to allowed URLs → Tools > Options > Expert Advisors > Allow WebRequests");
      else
         Print("PyP EA: WebRequest error ", err);
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
   if (body == "" || body == "null" || StringFind(body, "signal") < 0) return;

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
   int    ts         = (int)ParseJsonDouble(body, "timestamp");

   //--- Deduplicate
   if (signal == "" || ts <= (int)lastSignalTime) return;
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

   if (signal == "BUY")  ExecuteTrade(pair, OP_BUY,  sl_price, tp_price, lot_size, risk_pct, sl_pct, tp_pct, server_slippage);
   if (signal == "SELL") ExecuteTrade(pair, OP_SELL, sl_price, tp_price, lot_size, risk_pct, sl_pct, tp_pct, server_slippage);
}

string BuildSignalUrl() {
   string pair = Symbol();
   StringReplace(pair, "/", "");
   StringReplace(pair, "_", "");
   StringReplace(pair, " ", "");

   string url = ApiUrl + "/api/mt4/signals?token=" + EAToken + "&since=" + IntegerToString((int)lastSignalTime);
   if (DeploymentId != "") url += "&deployment_id=" + DeploymentId;
   if (pair != "") url += "&pair=" + pair;
   url += "&timeframe=" + NormalizeTimeframe(Period());
   return url;
}

string NormalizeTimeframe(int tf) {
   switch (tf) {
      case PERIOD_M1: return "1m";
      case PERIOD_M5: return "5m";
      case PERIOD_M15: return "15m";
      case PERIOD_M30: return "30m";
      case PERIOD_H1: return "1h";
      case PERIOD_H4: return "4h";
      case PERIOD_D1: return "1d";
      case PERIOD_W1: return "1w";
      case PERIOD_MN1: return "1mo";
   }
   return "1h";
}

//+------------------------------------------------------------------+
void ExecuteTrade(string pair, int orderType,
                  double server_sl, double server_tp, double server_lots,
                  double risk_pct, double sl_pct, double tp_pct, double server_slippage_pips) {

   if (CloseOnReverse) CloseOpposite(pair, orderType);

   RefreshRates();

   double price = (orderType == OP_BUY)
                  ? MarketInfo(pair, MODE_ASK)
                  : MarketInfo(pair, MODE_BID);

   if (price <= 0) {
      Print("PyP EA: Invalid price for ", pair);
      return;
   }

   double point    = MarketInfo(pair, MODE_POINT);
   int    digits   = (int)MarketInfo(pair, MODE_DIGITS);
   double pipValue = (digits == 3 || digits == 5) ? point * 10 : point;
   double tickValue = MarketInfo(pair, MODE_TICKVALUE);
   double tickSize  = MarketInfo(pair, MODE_TICKSIZE);
   double minLot    = MarketInfo(pair, MODE_MINLOT);
   double maxLot    = MarketInfo(pair, MODE_MAXLOT);
   double lotStep   = MarketInfo(pair, MODE_LOTSTEP);
   int dynamicSlippage = (server_slippage_pips > 0)
                         ? (int)MathMax(1, MathRound((server_slippage_pips * pipValue) / point))
                         : Slippage;

   //--- Resolve SL
   double sl = 0;
   if (ManualSL_Pips > 0) {
      sl = (orderType == OP_BUY)
           ? price - ManualSL_Pips * pipValue
           : price + ManualSL_Pips * pipValue;
   } else if (server_sl > 0) {
      sl = server_sl;
   } else if (sl_pct > 0) {
      double slDistance = price * (sl_pct / 100.0);
      sl = (orderType == OP_BUY)
           ? price - slDistance
           : price + slDistance;
   }

   //--- Resolve lot size
   double lots = (ManualLotSize > 0) ? ManualLotSize : 0;
   if (lots <= 0 && server_lots > 0) lots = server_lots;
   if (lots <= 0 && risk_pct > 0 && sl > 0 && tickValue > 0 && tickSize > 0) {
      double riskAmount = AccountBalance() * (risk_pct / 100.0);
      double stopDistance = MathAbs(price - sl);
      double lossPerLot = (stopDistance / tickSize) * tickValue;
      if (lossPerLot > 0) lots = riskAmount / lossPerLot;
   }
   if (lots <= 0) lots = 0.01;
   if (lotStep > 0) lots = MathFloor(lots / lotStep) * lotStep;
   if (minLot > 0 && lots < minLot) lots = minLot;
   if (maxLot > 0 && lots > maxLot) lots = maxLot;

   //--- Resolve TP
   double tp = 0;
   if (ManualTP_Pips > 0) {
      tp = (orderType == OP_BUY)
           ? price + ManualTP_Pips * pipValue
           : price - ManualTP_Pips * pipValue;
   } else if (server_tp > 0) {
      tp = server_tp;
   } else if (tp_pct > 0) {
      double tpDistance = price * (tp_pct / 100.0);
      tp = (orderType == OP_BUY)
           ? price + tpDistance
           : price - tpDistance;
   }

   //--- Normalize to broker precision
   if (sl > 0) sl = NormalizeDouble(sl, digits);
   if (tp > 0) tp = NormalizeDouble(tp, digits);

   int ticket = OrderSend(pair, orderType, lots, price, dynamicSlippage,
                          sl, tp, "PyP Signal", MagicNumber, 0,
                          orderType == OP_BUY ? clrGreen : clrRed);

   if (ticket < 0)
      Print("PyP EA: OrderSend failed, error=", GetLastError());
   else
      Print("PyP EA: Order opened ticket=", ticket,
            " type=", (orderType == OP_BUY ? "BUY" : "SELL"),
            " price=", DoubleToString(price, digits),
            " SL=", DoubleToString(sl, digits),
            " TP=", DoubleToString(tp, digits),
            " lots=", DoubleToString(lots, 2));
}

//+------------------------------------------------------------------+
void CloseOpposite(string pair, int newType) {
   for (int i = OrdersTotal() - 1; i >= 0; i--) {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if (OrderSymbol() != pair || OrderMagicNumber() != MagicNumber) continue;
      if ((newType == OP_BUY  && OrderType() == OP_SELL) ||
          (newType == OP_SELL && OrderType() == OP_BUY)) {
         double closePrice = (OrderType() == OP_BUY)
                             ? MarketInfo(pair, MODE_BID)
                             : MarketInfo(pair, MODE_ASK);
         bool closed = OrderClose(OrderTicket(), OrderLots(), closePrice, Slippage, clrWhite);
         if (!closed)
            Print("PyP EA: Failed to close opposite order, error=", GetLastError());
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
