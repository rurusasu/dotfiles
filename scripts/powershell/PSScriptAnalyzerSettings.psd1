@{
    ExcludeRules = @(
        'PSUseOutputTypeCorrectly',
        'PSUseShouldProcessForStateChangingFunctions',
        'PSAvoidUsingWriteHost'
    )
    Severity = @('Error', 'Warning')
}
