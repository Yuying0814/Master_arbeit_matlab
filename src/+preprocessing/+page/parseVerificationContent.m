function pageIdx = parseVerificationContent(contents,customIds,index)
    pageIdx = [];
    positiveMask = false(1,numel(index));
    
    positiveCustomId = [contents(strcmp(strtrim(string([contents.content])),"yes")).custom_id];

    for i = 1:numel(positiveCustomId)
        positiveMask = positiveMask | strcmp(customIds,positiveCustomId(i));
        pageIdx = index(positiveMask);
    end
end

