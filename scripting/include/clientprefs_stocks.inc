#if defined _clientprefs_stocks_included
	#endinput
#endif

#define _clientprefs_stocks_included

#include <clientprefs>

methodmap Cookie_Stocks < Cookie
{
	public Cookie_Stocks(const char[] sName, const char[] sDescription, CookieAccess iAccess)
	{
		return view_as<Cookie_Stocks>(new Cookie(sName, sDescription, iAccess));
	}

	public bool GetBool(int iClient)
	{
		char sValue[4];
		this.Get(iClient, sValue, sizeof(sValue));

		return view_as<bool>(StringToInt(sValue));
	}

	public void SetBool(int iClient, bool bValue)
	{
		char sValue[4];
		IntToString(view_as<int>(bValue), sValue, sizeof(sValue));

		this.Set(iClient, sValue);
	}

	public int GetInt(int iClient)
	{
		char sValue[16];
		this.Get(iClient, sValue, sizeof(sValue));

		return StringToInt(sValue);
	}

	public void SetInt(int iClient, int iValue)
	{
		char sValue[16];
		IntToString(iValue, sValue, sizeof(sValue));

		this.Set(iClient, sValue);
	}

	public float GetFloat(int iClient)
	{
		char sValue[16];
		this.Get(iClient, sValue, sizeof(sValue));

		return StringToFloat(sValue);
	}

	public void SetFloat(int iClient, float flValue)
	{
		char sValue[16];
		FloatToString(flValue, sValue, sizeof(sValue));

		this.Set(iClient, sValue);
	}
}
