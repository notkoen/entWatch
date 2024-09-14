#if defined entWatch_class_config_trigger_included
	#endinput
#endif

#define entWatch_class_config_trigger_included

methodmap CConfigTrigger < StringMap
{
	public CConfigTrigger(CConfig hConfig = null)
	{
		StringMap stringMap = new StringMap();

		stringMap.SetValue("hConfig",           hConfig);

		stringMap.SetValue("iConfigID",         0);
		stringMap.SetValue("iHammerID",         0);
		stringMap.SetValue("iType",             0);

		return view_as<CConfigTrigger>(stringMap);
	}

	property CConfig hConfig
	{
		public get()
		{
			CConfig hValue;
			if (this.GetValue("hConfig", hValue))
				return hValue;

			return null;
		}
		public set(CConfig hValue)
		{
			this.SetValue("hConfig", hValue);
		}
	}

	property int iConfigID
	{
		public get()
		{
			int iValue;
			if (this.GetValue("iConfigID", iValue))
				return iValue;

			return -1;
		}
		public set(int iValue)
		{
			this.SetValue("iConfigID", iValue);
		}
	}

	property int iHammerID
	{
		public get()
		{
			int iValue;
			if (this.GetValue("iHammerID", iValue))
				return iValue;

			return -1;
		}
		public set(int iValue)
		{
			this.SetValue("iHammerID", iValue);
		}
	}

	property int iType
	{
		public get()
		{
			int iValue;
			if (this.GetValue("iType", iValue))
				return iValue;

			return -1;
		}
		public set(int iValue)
		{
			this.SetValue("iType", iValue);
		}
	}
}
