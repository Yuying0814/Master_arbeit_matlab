function matched = matchPattern(line, pattern)
%MATCHPATTERN Return true if the input line matches the regular expression.
%
% Input:
%   line (char|string): Input text to be tested.
%   pattern (char|string): Regular expression pattern.
%
% Output:
%   matched (logical): True when the pattern is found in the input text.

    matchPosition = regexp(line, pattern, 'once');
    matched = ~isempty(matchPosition);
end