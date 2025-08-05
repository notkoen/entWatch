#if defined entWatch_restrictions_included
	#endinput
#endif

#define entWatch_restrictions_included

/**
 *
 */
forward void EW_OnClientRestricted(int iAdmin, int iTarget, int iDuration);

/**
 *
 */
forward void EW_OnClientUnrestricted(int iAdmin, int iTarget);

/**
 *
 */
native bool EW_ClientRestrict(int iAdmin, int iTarget, int iDuration);

/**
 *
 */
native bool EW_ClientUnrestrict(int iAdmin, int iTarget);

/**
 *
 */
native bool EW_ClientRestricted(int iAdmin);

/**
 *
 */
public SharedPlugin __pl_entWatch_restrictions =
{
	name = "entWatch-restrictions",
	file = "entWatch-restrictions.smx",

	#if defined REQUIRE_PLUGIN
		required = 1
	#else
		required = 0
	#endif
};

#if !defined REQUIRE_PLUGIN
	public void __pl_entWatch_restrictions_SetNTVOptional()
	{
		MarkNativeAsOptional("EW_ClientRestrict");
		MarkNativeAsOptional("EW_ClientUnrestrict");
		MarkNativeAsOptional("EW_ClientRestricted");
	}
#endif
