//====================================================================================================
//
// Name: [entWatch] Server Command
// Author: zaCade & Prometheum
// Description: Handle the filtering of servercommand messages for [entWatch]
//
//====================================================================================================
// Requires Sourcemod Version: 1.11.0.6820 or above
//====================================================================================================
#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <dhooks>
#include <entWatch_core>

/* DYNAMICHOOKS */
DynamicHook g_hAcceptInput;

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Plugin myinfo =
{
	name         = "[entWatch] Server Command",
	author       = "zaCade & Prometheum",
	description  = "Handle the filtering of servercommand messages for [entWatch]",
	version      = EW_VERSION
};

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void OnPluginStart()
{
	LoadGameConfig();

	int iEntity = INVALID_ENT_REFERENCE;
	while ((iEntity = FindEntityByClassname(iEntity, "point_servercommand")) != INVALID_ENT_REFERENCE)
	{
		OnEntityCreated(iEntity, "point_servercommand");
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
stock void LoadGameConfig()
{
	GameData hGameConf;
	if ((hGameConf = new GameData("sdktools.games")) == null)
	{
		SetFailState("Couldn't load \"sdktools.games\" game config!");
		return;
	}

	// bool CBaseEntity::AcceptInput( const char *szInputName, CBaseEntity *pActivator, CBaseEntity *pCaller, variant_t Value, int outputID )
	int iAcceptInputOffset;
	if ((iAcceptInputOffset = hGameConf.GetOffset("AcceptInput")) == -1)
	{
		delete hGameConf;
		SetFailState("hGameConf.GetOffset(\"AcceptInput\") failed!");
		return;
	}

	if ((g_hAcceptInput = new DynamicHook(iAcceptInputOffset, HookType_Entity, ReturnType_Bool, ThisPointer_CBaseEntity)) == INVALID_HANDLE)
	{
		delete hGameConf;
		SetFailState("new DynamicHook(iAcceptInputOffset (%d), HookType_Entity, ReturnType_Bool, ThisPointer_CBaseEntity) failed!", iAcceptInputOffset);
		return;
	}

	g_hAcceptInput.AddParam(HookParamType_CharPtr);
	g_hAcceptInput.AddParam(HookParamType_CBaseEntity);
	g_hAcceptInput.AddParam(HookParamType_CBaseEntity);
	g_hAcceptInput.AddParam(HookParamType_Object, 20, DHookPass_ByVal|DHookPass_ODTOR|DHookPass_OCTOR|DHookPass_OASSIGNOP); //variant_t is a union of 12 (float[3]) plus two int type params 12 + 8 = 20
	g_hAcceptInput.AddParam(HookParamType_Int);

	delete hGameConf;
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void OnEntityCreated(int iEntity, const char[] sClassname)
{
	if (IsValidEntity(iEntity) && StrEqual(sClassname, "point_servercommand"))
	{
		g_hAcceptInput.HookEntity(Hook_Pre, iEntity, OnAcceptInput);
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public MRESReturn OnAcceptInput(int iEntity, DHookReturn hReturn, DHookParam hParams)
{
	char sInputName[128];
	hParams.GetString(1, sInputName, sizeof(sInputName));

	if (!StrEqual(sInputName, "Command", false))
		return MRES_Ignored;

	int iCaller = INVALID_ENT_REFERENCE;
	if (!hParams.IsNull(3))
		iCaller = hParams.Get(3);

	if (IsValidEntity(iCaller) && EW_IsEntityItem(iCaller))
	{
		hReturn.Value = false;
		return MRES_Supercede;
	}

	return MRES_Ignored;
}
