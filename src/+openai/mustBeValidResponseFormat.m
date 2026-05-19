function mustBeValidResponseFormat(responseFormat)
    if ischar(responseFormat) || (isstring(responseFormat) && isscalar(responseFormat))
        validFormats = ["text","json"];
        if ~any(strtrim(string(lower(responseFormat))) == validFormats)
            error("OpenaiTaskAgent:InvalidResponseFormat", ...
                "ResponseFormat must be ""text"", ""json"", or a scalar struct.");
        end
        return;
    end
    
    if isstruct(responseFormat)
        if ~isscalar(responseFormat)
            error("OpenaiTaskAgent:InvalidResponseFormat", ...
                "ResponseFormat struct must be scalar.");
        end
        return;
    end

    error("OpenaiTaskAgent:InvalidResponseFormat", ...
        "ResponseFormat must be ""text"", ""json"", or a scalar struct.");
end
