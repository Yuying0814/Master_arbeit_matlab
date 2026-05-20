function userRequest = buildPageRequest(pages,reqName)
    arguments
        pages (1,:) struct
        reqName (1,1) string
    end
    
    keptFields = ["index", "markdown","tables","classification"];
    fields = string(fieldnames(pages));
    rmFields = setdiff(fields, keptFields);
    pages = rmfield(pages, rmFields);

    preContent = "";
    userRequest = repmat(struct("id","","userPrompt",""),1,numel(pages));

    for i=1:numel(pages)
        id = sprintf("%s_%d",reqName,i);
        context = struct( ...
        "current_page", pages(i), ...
        "previous_content", preContent);
        userPrompt = jsonencode(context);
        
        userRequest(i).id = string(id);
        userRequest(i).userPrompt = string(userPrompt);
        preContent = getPageTail(pages(i));
    end
end


function pageTail = getPageTail(page)
    text = preprocessing.utils.extractTextFrom(page);
    text = char(text);
    [~, chPos] = regexp(text, '\S+', 'match', 'start');

    if isempty(chPos)
        pageTail = "";
        return
    end

    wordCounts = numel(chPos);
    startWordIdx = max(1,ceil(wordCounts/2));
    startChIdx = chPos(startWordIdx);

    pageTail = string(text(startChIdx:end));
end

