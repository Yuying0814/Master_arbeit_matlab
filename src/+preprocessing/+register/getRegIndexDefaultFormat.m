function responseFormat = getRegIndexDefaultFormat()
    registers(1) = struct('name',"",'adress',"",'bank',"",'page',"",'source_index',"");
    registers(2) = struct('name',"",'adress',"",'bank',"",'page',"",'source_index',"");
    responseFormat = struct("registers",registers);
end

