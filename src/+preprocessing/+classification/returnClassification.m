function outPages = returnClassification(pages,contents)
    defaultValue = preprocessing.classification.getDefaultFormat();
    
    customIds = [contents.custom_id];
    for i = 1:numel(customIds)
        customId = customIds(i);
        contentIdx = find(strcmp(customId, [contents.custom_id]), 1);

        if isempty(contentIdx) || contents(contentIdx).not_finished
            pages(i).classification = defaultValue;
            continue
        end

        pages(i).classification = contents(contentIdx).content;
    end
end

