//+------------------------------------------------------------------+
//|                                                       PyP EA.mq5 |
//|                                          PyP Trading Platform    |
//|                                    https://pyp.stanlink.online   |
//+------------------------------------------------------------------+
#property copyright "PyP Trading Platform"
#property link      "https://pyp.stanlink.online"
#property version   "1.00"

#include <Trade\Trade.mqh>

input string EAToken       = "";         // EA Token (from PyP dashboard)
input string ApiUrl        = "https://api.pyp.stanlink.online"; // API URL
input double LotSize       = 0.1;        // Lot Size
input ulong  MagicNumber   = 20260101;   // Magic Number
input int    Slippage      = 3;          // Slippage (points)
input bool   EnableTrading = true;       // Enable Auto Trading

CTrade trade;
datetime lastSignalTime = 0;

//+------------------------------------------------------------------+
int OnInit() {
   if (EAToken == "") {
      Alert("PyP EA: EAToken is required. Get it from your PyP dashboard.");
      return INIT_FAILED;
   }
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   EventSetTimer(5);
   Print("PyP EA initialized. Token: ", StringSubstr(EAToken, 0, 8), "...");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   EventKillTimer();
}

//+------------------------------------------------------------------+
void OnTimer() {
   if (!EnableTrading) return;
   FetchAndExecuteSignal();
}

//+------------------------------------------------------------------+
void FetchAndExecuteSignal() {
   string url     = ApiUrl + "/api/mt4/signals?token=" + EAToken + "&since=" + IntegerToString((long)lastSignalTime);
   string headers = "Content-Type: application/json\r\n";
   char   post[];
   char   result[];
   string resultHeaders;

   int res = WebRequest("GET", url, headers, 5000, post, result, resultHeaders);

   if (res == -1) {
      int err = GetLastError();
      if (err == 4060) Print("PyP EA: Add ", ApiUrl, " to MT5 allowed URLs (Tools > Options > Expert Advisors)");
      else Print("PyP EA: WebRequest error ", err);
      return;
   }

   if (res != 200) {
      Print("PyP EA: API returned HTTP ", res);
      return;
   }

   string body = CharArrayToString(result);
   if (body == "" || body == "null" || StringFind(body, "signal") < 0) return;

   string signal = ParseJsonString(body, "signal");
   string pair   = ParseJsonString(body, "pair");
   double conf   = ParseJsonDouble(body, "confidence");
   long   ts     = (long)ParseJsonDouble(body, "timestamp");

   if (signal == "" || ts <= (long)lastSignalTime) return;
   lastSignalTime = (datetime)ts;

   StringReplace(pair, "/", "");
   StringReplace(pair, "_", "");
   if (pair == "") pair = Symbol();

   Print("PyP EA: Signal=", signal, " Pair=", pair, " Conf=", DoubleToString(conf, 2));

   if (signal == "BUY")  ExecuteTrade(pair, ORDER_TYPE_BUY);
   if (signal == "SELL") ExecuteTrade(pair, ORDER_TYPE_SELL);
}

//+------------------------------------------------------------------+
void ExecuteTrade(string pair, ENUM_ORDER_TYPE orderType) {
   CloseOpposite(pair, orderType);

   double price = (orderType == ORDER_TYPE_BUY)
                  ? SymbolInfoDouble(pair, SYMBOL_ASK)
                  : SymbolInfoDouble(pair, SYMBOL_BID);

   if (price <= 0) {
      Print("PyP EA: Invalid price for ", pair);
      return;
   }

   bool ok = (orderType == ORDER_TYPE_BUY)
             ? trade.Buy(LotSize, pair, price, 0, 0, "PyP Signal")
             : trade.Sell(LotSize, pair, price, 0, 0, "PyP Signal");

   if (!ok) Print("PyP EA: Order failed, error=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   else Print("PyP EA: Order opened type=", EnumToString(orderType), " price=", price);
}

//+------------------------------------------------------------------+
void CloseOpposite(string pair, ENUM_ORDER_TYPE newType) {
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket)) continue;
      if (PositionGetString(POSITION_SYMBOL) != pair) continue;
      if (PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber) continue;

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
