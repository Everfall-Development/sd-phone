-- MDT app - the Mobile Police Terminal that ships on sd-tablet. Every threshold
-- the server enforces is declared here and nowhere else: the UI only ever hides
-- controls, it never grants them.
return {
    -- Departments whose members reach the MDT. A player's ACTIVE framework job
    -- must appear here or every callback refuses, including the reads.
    --   job       framework job name
    --   type      'leo' | 'ems' | 'doj' - drives terminology on the frontend
    --   label     full department name shown in the header strip
    --   short     abbreviation used on the seal
    --   seal      DepartmentSeal artwork id ('lspd', 'bcso', 'sasp', 'doj', 'ems')
    --   accent    department colour, hex
    --   callsign  prefix for auto-generated callsigns ('LS' -> LS-104)
    --   bossGrade ESX-only boss threshold (ESX has no isboss flag)
    Departments = {
        {
            job       = 'police',
            type      = 'leo',
            label     = 'Los Santos Police Department',
            short     = 'LSPD',
            seal      = 'lspd',
            accent    = '#1D4ED8',
            callsign  = 'LS',
            bossGrade = 4,
        },
        {
            job       = 'sheriff',
            type      = 'leo',
            label     = 'Blaine County Sheriff Office',
            short     = 'BCSO',
            seal      = 'bcso',
            accent    = '#166534',
            callsign  = 'BC',
            bossGrade = 4,
        },
        {
            job       = 'sasp',
            type      = 'leo',
            label     = 'San Andreas State Police',
            short     = 'SASP',
            seal      = 'sasp',
            accent    = '#7C2D12',
            callsign  = 'SA',
            bossGrade = 4,
        },
    },

    -- When true a boss of their department (QBCore/QBox `isboss` flag, ESX
    -- grade >= bossGrade) holds every permission below. The chain-of-command
    -- guard on roster.grade / roster.dismiss still applies to a boss: nobody
    -- re-grades a peer, a superior, or themselves.
    BossBypass = true,

    -- Permission key -> MINIMUM job grade. A key that is not listed here is
    -- DENIED, not permitted, so a fresh install behaves predictably. Grades are
    -- the framework's own ladder, so grade 4 on a three-rank job simply means
    -- "nobody but a boss".
    Permissions = {
        ['home.view']        = 0,
        ['persons.view']     = 0,
        ['profiles.view']    = 0,
        ['vehicles.view']    = 0,
        ['reports.view']     = 0,
        ['reports.create']   = 0,
        ['reports.edit.own'] = 0,
        ['cases.view']       = 0,
        ['warrants.view']    = 0,
        ['offences.view']    = 0,
        ['roster.view']      = 0,
        ['employees.view']   = 0,
        ['dispatch.view']    = 0,
        ['dispatch.attach']  = 0,
        ['dispatch.status']  = 0,
        ['chat.view']        = 0,
        ['chat.send']        = 0,
        ['bulletins.view']   = 0,
        ['me.update']        = 0,

        ['persons.edit']     = 1,
        ['vehicles.edit']    = 1,
        ['cases.create']     = 1,
        ['cases.edit']       = 1,
        ['jail.view']        = 1,

        ['warrants.issue']   = 2,
        ['jail.book']        = 2,

        ['reports.edit.any'] = 3,
        ['warrants.close']   = 3,
        ['bulletins.manage'] = 3,
        ['roster.callsign']  = 3,
        ['roster.radio']     = 3,

        ['reports.delete']   = 4,
        ['cases.delete']     = 4,
        ['offences.delete']  = 4,
        ['offences.manage']  = 4,
        ['roster.grade']     = 4,
        ['roster.dismiss']   = 4,
        ['logs.view']        = 4,
    },

    -- Booking and sentencing. Months and fine are always derived server-side
    -- from the report's charge rows; these only bound what an officer may take
    -- OFF that figure.
    Jail = {
        MaxFine            = 25000, -- hard ceiling on a single citation
        MaxReductionMonths = 12,    -- most an officer may cut from a sentence
        MaxMonths          = 240,   -- hard ceiling on a single sentence
        Resource           = 'auto', -- 'auto' | 'qbx_prison' | 'qb-prison' | 'xt-prison'
        JailAccount        = 'bank', -- account a citation is debited from
    },

    -- Warrants. Closing a warrant expires it rather than deleting it, so the
    -- record survives for the audit trail.
    Warrants = {
        DefaultExpiryDays = 7,
        MaxExpiryDays     = 90,
        MaxBond           = 500000,
    },

    -- Dispatch is entirely in memory. TTL is how long a call stays on the board
    -- with nobody attached before it expires.
    Dispatch = {
        CallTTL        = 900,      -- seconds
        MaxCalls       = 60,
        CallsignFormat = '%s-%03d', -- prefix, sequence
        SweepSeconds   = 15,
    },

    -- Department radio channel. In-memory ring buffer, nothing persisted.
    Chat = {
        MaxMessages = 50,
        MaxLength   = 300,
        RateWindow  = 60000, -- ms
        RateMax     = 20,    -- messages per window
    },

    -- Row caps for the paginated master lists.
    Paging = {
        PageSize    = 25,
        MaxPageSize = 50,
        MaxPage     = 400,
    },

    -- Report types offered in the editor. Must match the ReportType union in
    -- web/src/apps/mdt/data.ts.
    ReportTypes = { 'Incident', 'Traffic', 'Arrest', 'Investigation', 'Warrant' },

    -- Officer-set flags offered on a citizen record. Must match PERSON_FLAGS in
    -- web/src/apps/mdt/data.ts.
    PersonFlags = { 'wanted', 'armed', 'gang', 'mental_health', 'flight_risk', 'informant' },

    -- Content caps for officer-authored text.
    Limits = {
        ReportTitle   = 160,
        ReportBody    = 12000,
        CaseTitle     = 160,
        CaseSummary   = 4000,
        CaseNote      = 1000,
        PersonNotes   = 4000,
        VehicleNotes  = 2000,
        BulletinTitle = 120,
        BulletinBody  = 4000,
        Callsign      = 12,
        RadioChannel  = 12,
        MediaUrl      = 512,
        Charges       = 40, -- charge lines per report
        Involved      = 24, -- involved persons per report
    },
}
